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

/** latest: { paramId: { v, t, ... } } → summary for gamified UI. */
export function summarize(latest, { includeEnv = false } = {}) {
  // Environment is shown separately; personal readiness = physiological data only.
  const items = [];
  for (const p of PARAMS) {
    if (!includeEnv && p.env) continue;
    const m = latest?.[p.id];
    if (!m || m.v == null) continue;
    items.push({ param: p, ...evaluate(p, m.v), v: m.v });
  }
  const counts = { ok: 0, warn: 0, crit: 0 };
  items.forEach(i => counts[i.status]++);
  const score = items.length ? Math.round(items.reduce((s, i) => s + i.score, 0) / items.length) : null;
  // A single critical parameter caps the readiness score so it can't hide.
  const readiness = score == null ? null : counts.crit ? Math.min(score, 45) : counts.warn ? Math.min(score, 79) : score;
  const overall = counts.crit ? STATUS.CRIT : counts.warn ? STATUS.WARN : items.length ? STATUS.OK : STATUS.NONE;
  return { items, counts, score, readiness, overall };
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
