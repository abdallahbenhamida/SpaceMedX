// =============================================================================
// DataMonitoringCircle — 2D disk (SVG).
// 12 sectors (organ systems, see params.SECTORS). Every parameter is a radial
// axis inside its sector with its own coloured scale
// (red | yellow | green | yellow | red, gray = no data / locked) and a marker
// at the normalised value. Scale-independent: positions come from scoring.normalize.
// =============================================================================
import { SECTORS, PARAMS, DISK_PARAMS, paramName } from '../params.js';
import { evaluate, normalize, STATUS_COLOR } from '../scoring.js';
import { s, clear } from '../ui.js';
import { t, lang } from '../i18n.js';

const SIZE = 800, C = SIZE / 2, R = 236, R0 = 46;

function polar(r, deg) { const a = (deg * Math.PI) / 180; return [C + r * Math.cos(a), C + r * Math.sin(a)]; }
function sectorAngle(id) { return -90 + (id - 1) * 30; }

export function paramAngles(params = DISK_PARAMS) {
  const out = {};
  for (const sec of SECTORS) {
    const list = params.filter(p => p.sector === sec.id);
    const n = list.length, spread = Math.min(25, n * 5);
    list.forEach((p, i) => { out[p.id] = sectorAngle(sec.id) + (n === 1 ? 0 : -spread / 2 + (spread * i) / (n - 1)); });
  }
  return out;
}

/**
 * @param {HTMLElement} host
 * @param {object} opts
 *   latest     { paramId: { v, locked } }
 *   showValues physician mode (raw value in tooltip)
 *   center     { label, value, status } text in the middle
 *   onSelect   (paramId) => void
 *   selected   paramId to highlight
 *   compact    hide parameter labels
 */
export function renderDisk(host, opts = {}) {
  const { latest = {}, showValues = false, center, onSelect, selected, compact = false, params = DISK_PARAMS } = opts;
  clear(host);
  const svg = s('svg', { viewBox: `0 0 ${SIZE} ${SIZE}`, class: 'disk2d', role: 'img', 'aria-label': t('tile.disk') });
  const angles = paramAngles(params);

  // grid: concentric 12-gons
  const g = s('g', { class: 'disk-grid' });
  for (let k = 0; k <= 5; k++) {
    const r = R0 + ((R - R0) * k) / 5;
    const pts = Array.from({ length: 12 }, (_, i) => polar(r, -90 + i * 30 + 15).join(',')).join(' ');
    g.append(s('polygon', { points: pts, class: k === 5 ? 'ring outer' : 'ring' }));
  }
  // sector separators + labels
  for (const sec of SECTORS) {
    const a = sectorAngle(sec.id);
    const [x1, y1] = polar(R0 * 0.6, a + 15), [x2, y2] = polar(R + 100, a + 15);
    g.append(s('line', { x1, y1, x2, y2, class: 'sep' }));
    const [lx, ly] = polar(R + 128, a);
    g.append(s('text', { x: lx, y: ly - 6, class: 'sec-roman', 'text-anchor': 'middle' }, sec.roman));
    g.append(s('text', { x: lx, y: ly + 9, class: 'sec-name', 'text-anchor': 'middle' }, t(sec.key)));
  }
  svg.append(g);

  // parameter axes
  const axes = s('g', { class: 'disk-axes' });
  for (const p of params) {
    const a = angles[p.id];
    const m = latest[p.id];
    const locked = m?.locked, has = m && m.v != null;
    const bounds = [0, normalize(p, p.warn[0]), normalize(p, p.ok[0]), normalize(p, p.ok[1]), normalize(p, p.warn[1]), 1];
    const cols = ['crit', 'warn', 'ok', 'warn', 'crit'];
    const grp = s('g', { class: `axis ${selected === p.id ? 'sel' : ''}`, tabindex: 0, 'data-param': p.id });
    // gray caps (as in the reference): small segment before/after the scale
    const cap = (r1, r2) => { const [x1, y1] = polar(r1, a), [x2, y2] = polar(r2, a); grp.append(s('line', { x1, y1, x2, y2, class: 'seg cap' })); };
    const r = f => R0 + 8 + (R - R0 - 16) * f;
    cap(R0, R0 + 8); cap(R - 8, R);
    for (let i = 0; i < 5; i++) {
      if (bounds[i + 1] - bounds[i] < 0.002) continue;
      const [x1, y1] = polar(r(bounds[i]), a), [x2, y2] = polar(r(bounds[i + 1]), a);
      grp.append(s('line', { x1, y1, x2, y2, class: `seg ${has ? cols[i] : 'none'}`, stroke: has ? STATUS_COLOR[cols[i]] : STATUS_COLOR.none }));
    }
    let tip = `${paramName(p, lang())}`;
    if (has) {
      const ev = evaluate(p, m.v);
      const [mx, my] = polar(r(ev.pos), a);
      const [ix, iy] = polar(r(0), a);
      grp.append(s('line', { x1: ix, y1: iy, x2: mx, y2: my, class: `val val-${ev.status}`, stroke: STATUS_COLOR[ev.status] }));
      grp.append(s('circle', { cx: mx, cy: my, r: 6.5, class: `marker m-${ev.status}`, fill: STATUS_COLOR[ev.status] }));
      tip += `\n${t('status.' + ev.status)} · ${t('common.score')}: ${ev.score}/100` + (showValues ? `\n${m.v} ${p.unit}  (ok ${p.ok[0]}–${p.ok[1]})` : '');
      grp.classList.add(`st-${ev.status}`);
    } else tip += `\n${locked ? '🔒 ' + t('privacy.locked') : t('common.noData')}`;
    grp.append(s('title', {}, tip));
    if (!compact) {
      const [tx, ty] = polar(R + 12, a);
      const deg = a > 90 || a < -90 ? a + 180 : a;
      const txt = s('text', { x: tx, y: ty, class: 'axis-label', 'text-anchor': a > 90 || a < -90 ? 'end' : 'start', 'dominant-baseline': 'middle', transform: `rotate(${deg} ${tx} ${ty})` }, (locked ? '🔒 ' : '') + short(paramName(p, lang())));
      grp.append(txt);
    }
    if (onSelect) { grp.addEventListener('click', () => onSelect(p.id)); grp.addEventListener('keydown', e => { if (e.key === 'Enter') onSelect(p.id); }); grp.style.cursor = 'pointer'; }
    axes.append(grp);
  }
  svg.append(axes);

  // centre
  if (center) {
    svg.append(s('circle', { cx: C, cy: C, r: R0 - 6, class: `center-c st-${center.status || 'none'}` }));
    svg.append(s('text', { x: C, y: C + 2, class: 'center-v', 'text-anchor': 'middle', 'dominant-baseline': 'middle' }, center.value ?? '–'));
    if (center.label) svg.append(s('text', { x: C, y: C + 22, class: 'center-l', 'text-anchor': 'middle' }, center.label));
  }
  host.append(svg);
  return svg;
}

function short(name, max = 17) { return name.length > max ? name.slice(0, max - 1) + '…' : name; }
