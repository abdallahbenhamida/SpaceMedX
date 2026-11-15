// =============================================================================
// Mock backend — same interface as LiveApi, used when config.mode = "mock"
// (or as fallback in "auto"). State that users create (warnings, consents,
// journal, uploads, settings, evaluations) is kept in localStorage, so when the
// three projects are served from the same origin they can talk to each other
// in the demo (e.g. a Team Leader warning shows up on the Single User page).
// =============================================================================
import { PARAMS, PARAM_BY_ID } from './params.js';

const STORE_KEY = 'shm_mock_store_v2';

// ---- deterministic pseudo-random -------------------------------------------
function hash(str) { let h = 2166136261; for (const c of str) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; }
function rng(seed) { let s = seed >>> 0; return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const uid = (p = 'id') => `${p}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;

// ---- static demo population --------------------------------------------------
export const TEAMS = [
  { id: 'team-moon', name: 'Artemis Base Alpha', frame: 'moon', timezone: 'LTC', base: { lat: -89.45, lon: -137.3, name: 'Shackleton rim' } },
  { id: 'team-iss', name: 'ISS Expedition 75', frame: 'station', timezone: 'UTC', base: { module: 'Destiny' } },
  { id: 'team-earth', name: 'HUNOR Analog Mission', frame: 'earth', timezone: 'Europe/Budapest', base: { lat: 47.5316, lon: 19.0402, name: 'Budapest' } },
];

//  • ISS: the Expedition 75 crew aboard the station in November 2026
//    (Soyuz MS-29: Dubrov — ISS commander, Kikina, Menon;
//     SpaceX Crew-13: Watkins, Delaney, Kutryk, Teteryatnikov)
//  • Moon base (fictional scenario): the Artemis II lunar fly-by crew
//  • Earth analog (fictional scenario): HUNOR / Ax-4 astronauts incl. Hungary's Tibor Kapu
const PEOPLE = [
  // team-moon
  ['u-101', 'Reid Wiseman', 'team-moon', 'teamleader', '#4fc3f7'],
  ['u-102', 'Victor Glover', 'team-moon', 'user', '#ff8a65'],
  ['u-103', 'Christina Koch', 'team-moon', 'user', '#ba68c8'],
  ['u-104', 'Jeremy Hansen', 'team-moon', 'user', '#aed581'],
  // team-iss — Expedition 75 (Nov 2026)
  ['u-201', 'Pyotr Dubrov', 'team-iss', 'teamleader', '#64b5f6'],
  ['u-202', 'Anna Kikina', 'team-iss', 'user', '#f06292'],
  ['u-203', 'Anil Menon', 'team-iss', 'user', '#ffd54f'],
  ['u-204', 'Jessica Watkins', 'team-iss', 'user', '#4db6ac'],
  ['u-205', 'Luke Delaney', 'team-iss', 'user', '#9575cd'],
  ['u-206', 'Joshua Kutryk', 'team-iss', 'user', '#e57373'],
  ['u-207', 'Sergei Teteryatnikov', 'team-iss', 'user', '#90a4ae'],
  // team-earth
  ['u-301', 'Tibor Kapu', 'team-earth', 'teamleader', '#81d4fa'],
  ['u-302', 'Gyula Cserényi', 'team-earth', 'user', '#ffb74d'],
  ['u-303', 'Sławosz Uznański-Wiśniewski', 'team-earth', 'user', '#e57373'],
  ['u-304', 'Shubhanshu Shukla', 'team-earth', 'user', '#a1887f'],
];

const GC_USERS = [
  { id: 'gc-op', name: 'Flight Director', role: 'operator', teamId: null, color: '#90caf9' },
  { id: 'gc-doc', name: 'Dr. Ilona Varga', role: 'physician', teamId: null, color: '#80cbc4' },
];

// Default profile pictures: illustrated avatars in common/assets/avatars/<id>.svg
// (a picture uploaded by the user via the profile dialog overrides it).
const AVATAR_BASE = new URL('../assets/avatars/', import.meta.url).href;
const defaultAvatar = id => `${AVATAR_BASE}${id}.svg`;

const STATION_MODULES = ['Destiny', 'Harmony', 'Columbus', 'Kibo', 'Zvezda', 'Unity', 'Tranquility'];

// Parameters each person keeps private by default (needs consent to view).
const DEFAULT_PRIVATE = { 'u-102': ['moodScore', 'cortisol'], 'u-203': ['moodScore'], 'u-302': ['bodyWeight', 'moodScore'], 'u-204': ['crp'] };

// A few deliberate anomalies so warnings are visible in the demo.
const ANOMALIES = {
  'u-102': { heartRate: 118, sleepTime: 5.1 },
  'u-103': { spo2: 89.5 },
  'u-202': { systolic: 146, cortisol: 26 },
  'u-205': { coreTemp: 38.6, crp: 22 },
  'u-303': { reactionTime: 380, sittingTime: 10.2 },
  'u-104': { boneDensityT: -1.8 },
};

const ENV_BY_FRAME = {
  moon: { radDoseRate: 58, radDoseMission: 210, cabinTemp: 21.5, humidity: 38, co2: 2900, ppO2: 21.0, cabinPressure: 70.3, noise: 52 },
  station: { radDoseRate: 21, radDoseMission: 96, cabinTemp: 22.8, humidity: 52, co2: 2400, ppO2: 21.3, cabinPressure: 101.3, noise: 58 },
  earth: { radDoseRate: 0.12, radDoseMission: 1.1, cabinTemp: 22, humidity: 45, co2: 650, ppO2: 21.2, cabinPressure: 101.0, noise: 42 },
};

function baseline(userId, p, frame) {
  if (ANOMALIES[userId]?.[p.id] != null) return ANOMALIES[userId][p.id];
  if (p.env) {
    // Moon pressure is a habitat-specific 70 kPa atmosphere: treat as ok there.
    return ENV_BY_FRAME[frame]?.[p.id] ?? (p.ok[0] + p.ok[1]) / 2;
  }
  const r = rng(hash(userId + p.id));
  const mid = (p.ok[0] + p.ok[1]) / 2, half = (p.ok[1] - p.ok[0]) / 2;
  return mid + (r() - 0.5) * half * 1.3;
}

function jitter(p, seedStr, tBucket, amp = 0.06) {
  const r = rng(hash(seedStr + tBucket));
  const span = (p.ok[1] - p.ok[0]) || (p.axis[1] - p.axis[0]) * 0.1;
  return (r() - 0.5) * span * amp * 2;
}

function round(p, v) {
  const span = p.axis[1] - p.axis[0];
  const dec = span <= 0.1 ? 3 : span <= 10 ? 2 : span <= 200 ? 1 : 0;
  return Number(v.toFixed(dec));
}

function locationFor(team, userId, rnd = Math.random) {
  if (team.frame === 'station') {
    const r = rng(hash(userId));
    return { frame: 'station', module: STATION_MODULES[Math.floor(r() * STATION_MODULES.length)], x: +(r() * 8 - 4).toFixed(1), y: +(r() * 2 - 1).toFixed(1) };
  }
  const r = rng(hash(userId + 'loc'));
  const spread = team.frame === 'moon' ? 0.6 : 0.05;
  return { frame: team.frame, lat: +(team.base.lat + (r() - 0.5) * spread).toFixed(4), lon: +(team.base.lon + (r() - 0.5) * spread * 4).toFixed(4) };
}

// ---- persistent store ----------------------------------------------------------
function load() {
  try { return JSON.parse(localStorage.getItem(STORE_KEY)) || null; } catch { return null; }
}
function freshStore() {
  const now = Date.now();
  return {
    warnings: [
      { id: uid('w'), fromId: 'gc-doc', fromName: 'Dr. Ilona Varga', toId: 'u-201', level: 'warn', parameter: 'coreTemp', message: 'Luke Delaney core temperature elevated — please check in with him.', time: new Date(now - 3600e3).toISOString(), ack: false },
    ],
    consents: [
      { id: uid('c'), requesterId: 'u-101', requesterName: 'Reid Wiseman', ownerId: 'u-102', scope: 'all-private', reason: 'Follow-up on sleep and mood trend', status: 'pending', time: new Date(now - 7200e3).toISOString() },
    ],
    journal: [],
    uploads: [],
    settings: {},
    evaluations: [],
    questionnaireResponses: [],
  };
}

export class MockApi {
  constructor(config) {
    this.cfg = config; this.mode = 'mock';
    this.user = JSON.parse(sessionStorage.getItem(`shm_mockuser_${config.app}`) || 'null');
  }
  get db() { return load() || freshStore(); }
  save(db) { localStorage.setItem(STORE_KEY, JSON.stringify(db)); }
  mutate(fn) { const db = this.db; const r = fn(db); this.save(db); return r; }
  async delay(v) { await new Promise(r => setTimeout(r, 60 + Math.random() * 120)); return structuredClone(v); }

  // ---- people ----------------------------------------------------------------
  allUsers() {
    const settings = this.db.settings;
    const users = PEOPLE.map(([id, name, teamId, role, color]) => ({ id, name, teamId, role, color, language: null, avatar: defaultAvatar(id) }))
      .concat(GC_USERS.map(u => ({ ...u, language: null, avatar: defaultAvatar(u.id) })));
    return users.map(u => { const st = settings[u.id] || {}; return { ...u, ...st, avatar: st.avatar || u.avatar }; });
  }
  findUser(id) { return this.allUsers().find(u => u.id === id); }

  demoAccounts() {
    const app = this.cfg.app;
    const all = this.allUsers();
    if (app === 'single-user') return all.filter(u => u.teamId);
    if (app === 'team-leader') return all.filter(u => u.role === 'teamleader');
    return all.filter(u => !u.teamId);
  }

  async login(username) {
    const u = this.allUsers().find(x => x.id === username || x.name.toLowerCase() === String(username).toLowerCase());
    if (!u) throw new Error('Unknown user');
    this.user = u;
    sessionStorage.setItem(`shm_mockuser_${this.cfg.app}`, JSON.stringify(u));
    return this.delay(u);
  }
  async logout() { this.user = null; sessionStorage.removeItem(`shm_mockuser_${this.cfg.app}`); }
  currentUser() { return this.user ? this.findUser(this.user.id) : null; }

  async getUser(id) { return this.delay(this.findUser(id)); }
  async saveUserSettings(userId, settings) {
    this.mutate(db => { db.settings[userId] = { ...(db.settings[userId] || {}), ...settings }; });
    return this.delay({ ok: true });
  }
  async listTeams() {
    const users = this.allUsers();
    return this.delay(TEAMS.map(t => ({ ...t, leaderId: users.find(u => u.teamId === t.id && u.role === 'teamleader')?.id, memberIds: users.filter(u => u.teamId === t.id).map(u => u.id) })));
  }
  async teamMembers(teamId) { return this.delay(this.allUsers().filter(u => u.teamId === teamId)); }

  // ---- access control (mirrors what the PHP server must enforce) -------------------
  privateSet(userId, db) {
    const set = new Set(DEFAULT_PRIVATE[userId] || []);
    db.uploads.filter(u => u.userId === userId && u.private).forEach(u => set.add(u.parameter));
    return set;
  }
  canSeePrivate(ownerId, db) {
    const viewer = this.currentUser();
    if (!viewer) return false;
    if (viewer.id === ownerId || viewer.role === 'physician') return true;
    return db.consents.some(c => c.ownerId === ownerId && c.requesterId === viewer.id && c.status === 'granted');
  }

  // ---- measurements -----------------------------------------------------------
  async latest(userId) {
    const db = this.db;
    const u = this.findUser(userId); if (!u) throw new Error('No such user');
    const team = TEAMS.find(t => t.id === u.teamId);
    const bucket = Math.floor(Date.now() / 15000);
    const priv = this.privateSet(userId, db), canPriv = this.canSeePrivate(userId, db);
    const values = {};
    for (const p of PARAMS) {
      let v = baseline(userId, p, team.frame) + (p.mode === 'continuous' ? jitter(p, userId + p.id, bucket) : 0);
      if (p.id === 'cabinPressure' && team.frame === 'moon') v = 99.5; // normalised for habitat
      let t = new Date(p.mode === 'continuous' ? Date.now() - 5000 : Date.now() - (1 + (hash(userId + p.id) % 40)) * 3600e3).toISOString();
      const up = db.uploads.filter(x => x.userId === userId && x.parameter === p.id).sort((a, b) => b.lastT.localeCompare(a.lastT))[0];
      if (up) { v = up.lastV; t = up.lastT; }
      const isPriv = priv.has(p.id);
      values[p.id] = isPriv && !canPriv ? { v: null, t, private: true, locked: true } : { v: round(p, v), t, private: isPriv };
    }
    return this.delay({ userId, timezone: team.timezone, frame: team.frame, location: locationFor(team, userId), values });
  }

  async measurements(userId, parameter, win = {}) {
    const p = PARAM_BY_ID[parameter];
    const u = this.findUser(userId); const team = TEAMS.find(t => t.id === u.teamId);
    const db = this.db;
    if (this.privateSet(userId, db).has(parameter) && !this.canSeePrivate(userId, db)) throw new Error('consent-required');
    const to = win.to ? new Date(win.to).getTime() : Date.now();
    const from = win.from ? new Date(win.from).getTime() : to - 24 * 3600e3;
    if (parameter === 'ecg') return this.delay([this.ecg(userId, to)]);
    const stepMs = p.mode === 'continuous' ? 10 * 60e3 : 6 * 3600e3;
    const samples = [];
    const base = baseline(userId, p, team.frame);
    for (let t = from; t <= to; t += stepMs) {
      const daily = Math.sin((t / 86400e3) * Math.PI * 2) * ((p.ok[1] - p.ok[0]) * 0.12);
      samples.push({ t: new Date(t).toISOString(), v: round(p, base + daily + jitter(p, userId + p.id, Math.floor(t / stepMs), 0.1)) });
    }
    const uploaded = db.uploads.filter(x => x.userId === userId && x.parameter === parameter).flatMap(x => x.samples);
    const loc = locationFor(team, userId);
    return this.delay([{
      schemaVersion: '1.0', measurementId: `m-${userId}-${parameter}`, userId, parameter, unit: p.unit,
      type: p.mode === 'continuous' ? 'series' : 'single',
      source: { device: p.source === 'sensor' ? 'Smart suit v2' : p.source, timezone: team.timezone, location: loc },
      samples: samples.concat(uploaded).sort((a, b) => a.t.localeCompare(b.t)),
    }]);
  }

  ecg(userId, to) {
    // Synthetic 10 s lead-II ECG at 250 Hz (physician view only).
    const fs = 250, n = fs * 10, r = rng(hash(userId + 'ecg'));
    const hr = baseline(userId, PARAM_BY_ID.heartRate, 'earth'); const rr = 60 / hr;
    const samples = [];
    for (let i = 0; i < n; i++) {
      const tt = i / fs, ph = (tt % rr) / rr;
      const g = (c, w, a) => a * Math.exp(-((ph - c) ** 2) / (2 * w * w));
      const v = g(0.18, 0.025, 0.12) + g(0.37, 0.008, -0.12) + g(0.4, 0.01, 1.1) + g(0.43, 0.009, -0.25) + g(0.68, 0.04, 0.3) + (r() - 0.5) * 0.03;
      samples.push(+v.toFixed(3));
    }
    return { schemaVersion: '1.0', userId, parameter: 'ecg', unit: 'mV', type: 'waveform', sampleRate: fs, start: new Date(to - 10000).toISOString(), values: samples };
  }

  async attachments(userId) {
    // Not a separate endpoint on the PHP server: attachments arrive inside measurement JSONs.
    const db = this.db;
    const fromUploads = db.uploads.filter(u => u.userId === userId && u.attachments?.length).flatMap(u => u.attachments.map(a => ({ ...a, time: u.lastT, private: u.private })));
    return this.delay([
      { kind: 'dicom', name: 'Cardiac ultrasound (4-chamber)', time: new Date(Date.now() - 26 * 3600e3).toISOString(), url: null },
      { kind: 'pdf', name: 'Blood panel report', time: new Date(Date.now() - 50 * 3600e3).toISOString(), url: null },
      { kind: 'image', name: 'Skin check photo', time: new Date(Date.now() - 80 * 3600e3).toISOString(), url: null },
      { kind: 'camera', name: 'Helmet camera', time: new Date().toISOString(), url: null, live: true },
      ...fromUploads,
    ]);
  }

  async upload(m) {
    if (!m?.userId || !m?.parameter || !Array.isArray(m.samples) || !m.samples.length) throw new Error('Invalid measurement JSON (userId, parameter, samples[] required)');
    const sorted = [...m.samples].sort((a, b) => String(a.t).localeCompare(String(b.t)));
    const last = sorted[sorted.length - 1];
    this.mutate(db => db.uploads.push({ id: uid('up'), userId: m.userId, parameter: m.parameter, private: !!m.private, samples: sorted, lastV: Number(last.v), lastT: new Date(last.t).toISOString(), attachments: m.attachments || [], meta: m.meta || {} }));
    return this.delay({ ok: true, stored: sorted.length });
  }

  // ---- journal & questionnaires ----------------------------------------------------
  async journalList(userId) {
    const db = this.db, canPriv = this.canSeePrivate(userId, db);
    return this.delay(db.journal.filter(j => j.userId === userId).map(j => j.private && !canPriv ? { ...j, text: null, meta: {}, locked: true } : j).sort((a, b) => b.time.localeCompare(a.time)));
  }
  async journalAdd(entry) {
    if (!entry.name || !entry.time) throw new Error('name and time are required');
    const e = { id: uid('j'), ...entry };
    this.mutate(db => db.journal.push(e));
    return this.delay(e);
  }
  async questionnaires() {
    return this.delay([
      { id: 'sleep', titleKey: 'q.sleep.title', parameter: 'sleepTime', frequency: 'daily', items: [
        { id: 'bed', type: 'time', key: 'q.sleep.bed' }, { id: 'wake', type: 'time', key: 'q.sleep.wake' },
        { id: 'quality', type: 'scale', min: 1, max: 5, key: 'q.sleep.quality' }, { id: 'awakenings', type: 'number', key: 'q.sleep.awakenings' } ] },
      { id: 'mood', titleKey: 'q.mood.title', parameter: 'moodScore', frequency: 'weekly', items: [
        { id: 'm1', type: 'scale', min: 0, max: 3, key: 'q.mood.m1' }, { id: 'm2', type: 'scale', min: 0, max: 3, key: 'q.mood.m2' },
        { id: 'm3', type: 'scale', min: 0, max: 3, key: 'q.mood.m3' }, { id: 'm4', type: 'scale', min: 0, max: 3, key: 'q.mood.m4' },
        { id: 'm5', type: 'scale', min: 0, max: 3, key: 'q.mood.m5' } ] },
    ]);
  }
  async submitQuestionnaire(resp) {
    this.mutate(db => db.questionnaireResponses.push({ id: uid('q'), ...resp }));
    if (resp.derived) await this.upload({ userId: resp.userId, parameter: resp.derived.parameter, private: !!resp.private, samples: [{ t: resp.time, v: resp.derived.value }], meta: { questionnaire: resp.questionnaireId } });
    return this.delay({ ok: true });
  }

  // ---- warnings -----------------------------------------------------------------
  async sendWarning(w) {
    const from = this.currentUser();
    const msg = { id: uid('w'), fromId: from?.id, fromName: from?.name, time: new Date().toISOString(), ack: false, ...w };
    this.mutate(db => db.warnings.push(msg));
    return this.delay(msg);
  }
  async inbox(userId) { return this.delay(this.db.warnings.filter(w => w.toId === userId).sort((a, b) => b.time.localeCompare(a.time))); }
  async sent(userId) { return this.delay(this.db.warnings.filter(w => w.fromId === userId).sort((a, b) => b.time.localeCompare(a.time))); }
  async ackWarning(id) { this.mutate(db => { const w = db.warnings.find(x => x.id === id); if (w) { w.ack = true; w.ackTime = new Date().toISOString(); } }); return this.delay({ ok: true }); }

  // ---- consent -----------------------------------------------------------------
  async requestConsent(req) {
    const me = this.currentUser();
    const c = { id: uid('c'), requesterId: me.id, requesterName: me.name, status: 'pending', time: new Date().toISOString(), scope: 'all-private', ...req };
    this.mutate(db => { db.consents = db.consents.filter(x => !(x.ownerId === c.ownerId && x.requesterId === c.requesterId && x.status === 'pending')); db.consents.push(c); });
    return this.delay(c);
  }
  async respondConsent(id, granted) {
    this.mutate(db => { const c = db.consents.find(x => x.id === id); if (c) { c.status = granted ? 'granted' : 'denied'; c.respondedAt = new Date().toISOString(); } });
    return this.delay({ ok: true });
  }
  async listConsents(userId) { return this.delay(this.db.consents.filter(c => c.ownerId === userId || c.requesterId === userId)); }

  // ---- physician evaluations ------------------------------------------------------
  async saveEvaluation(ev) { const e = { id: uid('ev'), time: new Date().toISOString(), physicianId: this.currentUser()?.id, physicianName: this.currentUser()?.name, ...ev }; this.mutate(db => db.evaluations.push(e)); return this.delay(e); }
  async listEvaluations(userId) { return this.delay(this.db.evaluations.filter(e => e.userId === userId).sort((a, b) => b.time.localeCompare(a.time))); }
}

export function resetMockStore() { localStorage.removeItem(STORE_KEY); }
