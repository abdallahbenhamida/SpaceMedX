// =============================================================================
// Scale-independent scoring.
// Every value is mapped (piece-wise linearly, in its own unit) to a normalised
// axis position 0..1, a status (ok / warn / crit) and a 0..100 score. The UI
// never needs to know the unit — only physicians see raw values.
// =============================================================================
import { PARAM_BY_ID, PARAMS } from './params.js';

// Visual bands along every axis (fraction of axis length):
//   0 ─ crit ─ .15 ─ warn ─ .30 ─── ok ─── .70 ─ warn ─ .85 ─ crit ─ 1
export const BANDS = { warnLo: 0.15, okLo: 0.30, okHi: 0.70, warnHi: 0.85 };

export const STATUS = { OK: 'ok', WARN: 'warn', CRIT: 'crit', NONE: 'none' };

export const STATUS_COLOR = {
  ok: '#2ecc71',
  warn: '#f5c242',
  crit: '#ff4d4f',
  none: '#5b6b85',
};

function lerp(a, b, t) { return a + (b - a) * t; }
function inv(a, b, v) { return b === a ? 0.5 : (v - a) / (b - a); }
const clamp01 = v => Math.max(0, Math.min(1, v));

export function getParam(p) { return typeof p === 'string' ? PARAM_BY_ID[p] : p; }

export function statusOf(param, value) {
  const p = getParam(param);
  if (!p || value === null || value === undefined || Number.isNaN(value)) return STATUS.NONE;
  if (value >= p.ok[0] && value <= p.ok[1]) return STATUS.OK;
  if (value >= p.warn[0] && value <= p.warn[1]) return STATUS.WARN;
  return STATUS.CRIT;
}

/** Normalised position 0..1 on the axis (piece-wise linear over the bands). */
export function normalize(param, value) {
  const p = getParam(param);
  if (!p || value == null) return null;
  const [amin, amax] = p.axis;
  const wlo = Math.max(amin, p.warn[0]), whi = Math.min(amax, p.warn[1]);
  const olo = Math.max(wlo, p.ok[0]), ohi = Math.min(whi, p.ok[1]);
  const v = Math.max(amin, Math.min(amax, value));
  // When a lower band collapses (one-sided parameter, e.g. SpO2 upper side or
  // CO2 lower side) the corresponding visual band is skipped.
  if (v < wlo) return lerp(0, BANDS.warnLo, inv(amin, wlo, v));
  if (v < olo) return lerp(BANDS.warnLo, BANDS.okLo, inv(wlo, olo, v));
  if (v <= ohi) {
    const lo = olo === amin ? 0 : BANDS.okLo;
    const hi = ohi === amax ? 1 : BANDS.okHi;
    return lerp(lo, hi, inv(olo, ohi, v));
  }
  if (v <= whi) return lerp(BANDS.okHi, BANDS.warnHi, inv(ohi, whi, v));
  return lerp(BANDS.warnHi, 1, inv(whi, amax, v));
}

/**
 * Score 0..100 for the non-medical (gamified) view:
 *   centre of healthy range → 100, edge of healthy → 75,
 *   edge of warning → 40, axis end → 0.
 */
export function scoreOf(param, value) {
  const p = getParam(param);
  if (!p || value == null) return null;
  const st = statusOf(p, value);
  const [olo, ohi] = p.ok, [wlo, whi] = p.warn, [amin, amax] = p.axis;
  if (st === STATUS.OK) {
    const mid = (olo + ohi) / 2, half = (ohi - olo) / 2 || 1;
    // One-sided ranges: being at the "good" extreme is perfect.
    const oneSidedLow = olo <= amin, oneSidedHigh = ohi >= amax;
    let d;
    if (oneSidedLow) d = (value - olo) / (ohi - olo || 1);
    else if (oneSidedHigh) d = (ohi - value) / (ohi - olo || 1);
    else d = Math.abs(value - mid) / half;
    return Math.round(100 - 25 * clamp01(d));
  }
  if (st === STATUS.WARN) {
    const t = value < olo ? inv(olo, wlo, value) : inv(ohi, whi, value);
    return Math.round(74 - 34 * clamp01(t));
  }
  const t = value < wlo ? inv(wlo, amin, value) : inv(whi, amax, value);
  return Math.round(39 - 39 * clamp01(t));
}

export function evaluate(param, value) {
  return { status: statusOf(param, value), score: scoreOf(param, value), pos: normalize(param, value) };
}

// ---- status categories ---------------------------------------------------------------
// Mission readiness is computed from five category statuses:
//   health        physiological parameters (all sectors except mental & environment)
//   mental        mental health — mood, cognition, isolation & confinement
//   environment   space radiation, gravity fields and habitat life support
//   location      do we receive position data (age of the newest position fix)
//   communication can we reach the person (age of last contact, unacknowledged warnings)
export const CATEGORIES = ['health', 'mental', 'environment', 'location', 'communication'];
export const CATEGORY_WEIGHTS = { health: 0.35, mental: 0.2, environment: 0.2, location: 0.1, communication: 0.15 };
export const CATEGORY_ICON = { health: '♥', mental: '◉', environment: '☢', location: '⌖', communication: '📡' };
// Freshness limits in minutes: ok ≤ ok, warning ≤ warn, critical beyond.
export const LINK_LIMITS = {
  location: { ok: 15, warn: 60 },
  communication: { ok: 10, warn: 60, unackedWarnMin: 30, unackedCritMin: 240 },
};

const minutesSince = (iso, now) => (iso ? Math.max(0, (now - new Date(iso).getTime()) / 60000) : null);

/** Score a data-age (minutes): fresh → 100, ok edge → 75, warn edge → 40, 4× warn → 0. */
export function freshness(ageMin, { ok, warn }) {
  if (ageMin == null) return { status: STATUS.CRIT, score: 0 };
  if (ageMin <= ok) return { status: STATUS.OK, score: Math.round(100 - 25 * clamp01(ageMin / ok)) };
  if (ageMin <= warn) return { status: STATUS.WARN, score: Math.round(74 - 34 * clamp01((ageMin - ok) / (warn - ok))) };
  return { status: STATUS.CRIT, score: Math.round(39 - 39 * clamp01((ageMin - warn) / (3 * warn))) };
}

const WORST = { none: 0, ok: 1, warn: 2, crit: 3 };
const worst = list => list.reduce((w, s) => (WORST[s] > WORST[w] ? s : w), STATUS.NONE);
/** Mean score, but one critical item caps at 45 and one warning item at 79, so nothing hides. */
function combine(items) {
  const counts = { ok: 0, warn: 0, crit: 0 };
  items.forEach(i => { if (counts[i.status] != null) counts[i.status]++; });
  if (!items.length) return { status: STATUS.NONE, score: null, counts };
  const mean = Math.round(items.reduce((s, i) => s + i.score, 0) / items.length);
  const score = counts.crit ? Math.min(mean, 45) : counts.warn ? Math.min(mean, 79) : mean;
  return { status: worst(items.map(i => i.status)), score, counts };
}

function paramCategory(items, cat) {
  const list = items.filter(i => i.param.category === cat);
  return { key: cat, kind: 'params', items: list, ...combine(list) };
}

/** Location status: is the position stream alive? */
export function locationStatus(latest, now = Date.now()) {
  if (!latest || !('locationTime' in latest)) return { key: 'location', kind: 'link', status: STATUS.NONE, score: null, items: [] };
  const age = minutesSince(latest.locationTime, now);
  const f = freshness(age, LINK_LIMITS.location);
  const item = { key: 'location.lastFix', time: latest.locationTime, age, ...f };
  return { key: 'location', kind: 'link', items: [item], ...combine([item]) };
}

/** Communication status: last contact + warnings the person has not acknowledged. */
export function communicationStatus(latest, now = Date.now()) {
  const c = latest?.comm;
  if (!c) return { key: 'communication', kind: 'link', status: STATUS.NONE, score: null, items: [] };
  const L = LINK_LIMITS.communication;
  const age = minutesSince(c.lastContact, now);
  const items = [{ key: 'comm.lastContact', time: c.lastContact, age, ...freshness(age, L) }];
  const n = c.unackedWarnings || 0;
  const oldest = minutesSince(c.oldestUnackedAt, now);
  let st = STATUS.OK, score = 100;
  if (n && oldest != null && oldest > L.unackedCritMin) { st = STATUS.CRIT; score = 30; }
  else if (n && oldest != null && oldest > L.unackedWarnMin) { st = STATUS.WARN; score = 60; }
  else if (n) score = 85;
  items.push({ key: 'comm.unacked', count: n, age: oldest, time: c.oldestUnackedAt, status: st, score });
  return { key: 'communication', kind: 'link', items, ...combine(items) };
}

/**
 * Summary for the gamified UI.
 * @param input either a `latest` response ({ values, locationTime, comm, … }) or a bare
 *              values map ({ paramId: { v, t } }, e.g. a team average). Location and
 *              communication are only scored when the latest response carries them.
 * @returns { items, counts, categories, score, readiness, overall }
 */
export function summarize(input, { now = Date.now() } = {}) {
  const isLatest = input && typeof input.values === 'object' && input.values !== null && !('v' in input.values);
  const values = isLatest ? input.values : (input || {});
  const items = [];
  for (const p of PARAMS) {
    const m = values?.[p.id];
    if (!m || m.v == null) continue;
    items.push({ param: p, ...evaluate(p, m.v), v: m.v });
  }
  const categories = {
    health: paramCategory(items, 'health'),
    mental: paramCategory(items, 'mental'),
    environment: paramCategory(items, 'environment'),
    location: locationStatus(isLatest ? input : null, now),
    communication: communicationStatus(isLatest ? input : null, now),
  };
  const scored = CATEGORIES.filter(c => categories[c].score != null);
  const wsum = scored.reduce((s, c) => s + CATEGORY_WEIGHTS[c], 0);
  const score = scored.length ? Math.round(scored.reduce((s, c) => s + categories[c].score * CATEGORY_WEIGHTS[c], 0) / wsum) : null;
  // A critical category caps readiness in the critical band, so it can't be averaged away.
  const anyCrit = scored.some(c => categories[c].status === STATUS.CRIT);
  const readiness = score == null ? null : anyCrit ? Math.min(score, 45) : score;
  const counts = { ok: 0, warn: 0, crit: 0 };
  items.forEach(i => counts[i.status]++);
  const overall = worst(scored.map(c => categories[c].status));
  return { items, counts, categories, score, readiness, overall };
}

export function readinessStatus(r) {
  if (r == null) return STATUS.NONE;
  return r >= 80 ? STATUS.OK : r >= 46 ? STATUS.WARN : STATUS.CRIT;
}

/** Gamification: level & rank derived from readiness + streak. */
export function rankFor(readiness, streakDays = 0) {
  const xp = Math.max(0, Math.round((readiness ?? 0) * 10 + streakDays * 150));
  const level = 1 + Math.floor(xp / 400);
  const ranks = ['rank.cadet', 'rank.specialist', 'rank.pilot', 'rank.commander', 'rank.legend'];
  return { xp, level, rankKey: ranks[Math.min(ranks.length - 1, Math.floor((level - 1) / 2))], nextAt: level * 400 };
}

/** Average latest values of several users (for team / aggregate disks). */
export function averageLatest(latestList) {
  const out = {};
  for (const p of PARAMS) {
    const vals = latestList.map(l => l?.[p.id]?.v).filter(v => v != null);
    if (vals.length) out[p.id] = { v: vals.reduce((a, b) => a + b, 0) / vals.length, n: vals.length };
  }
  return out;
}

/** Team / group readiness = mean of the members' own readiness (each with all five categories). */
export function averageReadiness(latestList) {
  const r = latestList.map(l => (l ? summarize(l).readiness : null)).filter(x => x != null);
  return r.length ? Math.round(r.reduce((a, b) => a + b, 0) / r.length) : null;
}

/** Mean category scores of a group (for the H/M/E/L/C chips of team cards). */
export function averageCategories(latestList) {
  const out = {};
  const sums = latestList.filter(Boolean).map(l => summarize(l));
  for (const c of CATEGORIES) {
    const list = sums.map(s => s.categories[c]).filter(x => x.score != null);
    if (!list.length) { out[c] = { key: c, status: STATUS.NONE, score: null }; continue; }
    const score = Math.round(list.reduce((a, x) => a + x.score, 0) / list.length);
    out[c] = { key: c, score, status: worst(list.map(x => x.status)) };
  }
  return out;
}
