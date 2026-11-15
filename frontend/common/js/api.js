// =============================================================================
// API client for the (existing) PHP server.
// All endpoint paths come from config.json → endpoints. GET parameters go in the
// query string, POST bodies are JSON. Auth: "Authorization: Bearer <token>"
// (+ optional X-API-Key). Every time window is sent in UTC together with the
// viewer's IANA time zone (tz) so the server can answer in either.
//
// createApi(config) returns the live client, the mock client, or an "auto"
// client that falls back to mock when the server is unreachable.
// =============================================================================
import { MockApi } from './mock.js';

export class ApiError extends Error {
  constructor(message, status, body) { super(message); this.status = status; this.body = body; }
}

export class LiveApi {
  constructor(config) {
    this.cfg = config;
    this.base = config.server.baseUrl.replace(/\/+$/, '') + '/';
    this.token = sessionStorage.getItem(`shm_token_${config.app}`) || null;
    this.user = JSON.parse(sessionStorage.getItem(`shm_user_${config.app}`) || 'null');
    this.mode = 'live';
  }

  url(name, query) {
    const path = this.cfg.endpoints[name];
    if (!path) throw new Error(`Unknown endpoint "${name}" — add it to config.json`);
    const u = new URL(path, this.base);
    if (query) for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null) u.searchParams.set(k, v);
    return u.toString();
  }

  async request(name, { method = 'GET', query, body } = {}) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), this.cfg.server.timeoutMs);
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    if (this.cfg.server.apiKey) headers['X-API-Key'] = this.cfg.server.apiKey;
    try {
      const res = await fetch(this.url(name, query), {
        method, headers, signal: ctrl.signal,
        body: body !== undefined ? JSON.stringify(body) : undefined,
        credentials: this.cfg.server.withCredentials ? 'include' : 'same-origin',
      });
      const text = await res.text();
      let data; try { data = text ? JSON.parse(text) : null; } catch { data = text; }
      if (!res.ok) throw new ApiError(data?.error || `HTTP ${res.status}`, res.status, data);
      // Server envelope { ok, data, error } is optional — unwrap when present.
      if (data && typeof data === 'object' && 'ok' in data && 'data' in data) {
        if (!data.ok) throw new ApiError(data.error || 'Server error', res.status, data);
        return data.data;
      }
      return data;
    } finally { clearTimeout(timer); }
  }

  get(name, query) { return this.request(name, { query }); }
  post(name, body) { return this.request(name, { method: 'POST', body }); }

  // ---- auth ---------------------------------------------------------------
  async login(username, password) {
    const r = await this.post('login', { username, password, app: this.cfg.app });
    this.token = r.token; this.user = r.user;
    sessionStorage.setItem(`shm_token_${this.cfg.app}`, r.token);
    sessionStorage.setItem(`shm_user_${this.cfg.app}`, JSON.stringify(r.user));
    return r.user;
  }
  async logout() {
    try { await this.post('logout', {}); } catch { /* ignore */ }
    this.token = null; this.user = null;
    sessionStorage.removeItem(`shm_token_${this.cfg.app}`);
    sessionStorage.removeItem(`shm_user_${this.cfg.app}`);
  }
  currentUser() { return this.user; }
  demoAccounts() { return []; }

  // ---- users & teams --------------------------------------------------------
  getUser(id) { return this.get('user', { id }); }
  saveUserSettings(userId, settings) { return this.post('userSettings', { userId, ...settings }); }
  listTeams() { return this.get('teams'); }
  teamMembers(teamId) { return this.get('teamMembers', { teamId }); }

  // ---- measurements ---------------------------------------------------------
  /** → { userId, timezone, location, values: { paramId: { v, t, private, locked } } } */
  latest(userId) { return this.get('latest', { userId }); }
  /** → [ measurement JSON (see docs/API.md) ] */
  measurements(userId, parameter, win) { return this.get('measurements', { userId, parameter, ...win }); }
  /** One JSON = one user's one measurement (single sample or a series). */
  upload(measurement) { return this.post('upload', measurement); }
  /** → [ { kind: dicom|image|pdf|camera|csv, name, url, time, private } ] */
  attachments(userId) { return this.get('attachments', { userId }); }

  // ---- journal & questionnaires ---------------------------------------------
  journalList(userId, win) { return this.get('journalList', { userId, ...win }); }
  journalAdd(entry) { return this.post('journalAdd', entry); }
  questionnaires() { return this.get('questionnaires'); }
  submitQuestionnaire(resp) { return this.post('questionnaireSubmit', resp); }

  // ---- warnings ------------------------------------------------------------
  sendWarning(w) { return this.post('warningSend', w); }
  inbox(userId) { return this.get('warningInbox', { userId }); }
  ackWarning(id) { return this.post('warningAck', { id }); }
  sent(userId) { return this.get('warningSent', { userId }); }

  // ---- consent (private data access) -------------------------------------------
  requestConsent(req) { return this.post('consentRequest', req); }
  respondConsent(id, granted) { return this.post('consentRespond', { id, granted }); }
  listConsents(userId) { return this.get('consentList', { userId }); }

  // ---- physician evaluations ------------------------------------------------
  saveEvaluation(ev) { return this.post('evaluationSave', ev); }
  listEvaluations(userId) { return this.get('evaluationList', { userId }); }
}

/** Live first; on network failure switch permanently to mock (demo). */
class AutoApi {
  constructor(config) {
    this.live = new LiveApi(config); this.mock = new MockApi(config);
    this.impl = this.live; this.mode = 'auto';
    return new Proxy(this, {
      get: (t, prop) => {
        if (prop in t && prop !== 'constructor') return t[prop];
        const fn = t.impl[prop];
        if (typeof fn !== 'function') return t.impl[prop];
        return async (...args) => {
          try { return await t.impl[prop](...args); }
          catch (e) {
            if (t.impl === t.live && !(e instanceof ApiError)) {
              console.warn('[api] server unreachable — falling back to mock data', e);
              t.impl = t.mock; t.mode = 'mock-fallback';
              return t.mock[prop](...args);
            }
            throw e;
          }
        };
      },
    });
  }
}

export function createApi(config) {
  if (config.mode === 'live') return new LiveApi(config);
  if (config.mode === 'auto') return new AutoApi(config);
  return new MockApi(config);
}
