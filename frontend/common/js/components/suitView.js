// =============================================================================
// Suit view — front silhouette of a crew member in a flight suit with the
// sensor/measurement points. Each point is coloured by the worst status of
// the parameters measured there; critical points pulse.
// =============================================================================
import { BODY_POINTS, PARAMS, paramName } from '../params.js';
import { evaluate, STATUS_COLOR } from '../scoring.js';
import { s, clear } from '../ui.js';
import { t, lang } from '../i18n.js';

const ORDER = { none: 0, ok: 1, warn: 2, crit: 3 };

const SILHOUETTE = [
  // helmet / head
  ['circle', { cx: 100, cy: 38, r: 25 }],
  ['rect', { x: 88, y: 60, width: 24, height: 14, rx: 5 }],
  // torso
  ['path', { d: 'M62 82 Q100 70 138 82 L146 150 Q140 196 132 214 L68 214 Q60 196 54 150 Z' }],
  // belt
  ['rect', { x: 66, y: 198, width: 68, height: 18, rx: 6 }],
  // arms
  ['path', { d: 'M62 84 Q44 90 42 120 L32 214 Q30 226 38 238 L48 236 L56 160 L66 120 Z' }],
  ['path', { d: 'M138 84 Q156 90 158 120 L168 214 Q170 226 162 238 L152 236 L144 160 L134 120 Z' }],
  // legs
  ['path', { d: 'M68 214 L132 214 L130 300 L124 392 L106 396 L102 262 L98 262 L94 396 L76 392 L70 300 Z' }],
  // boots
  ['rect', { x: 72, y: 388, width: 26, height: 18, rx: 6 }],
  ['rect', { x: 102, y: 388, width: 26, height: 18, rx: 6 }],
];

export function renderSuit(host, { latest = {}, color = '#4fc3f7', onSelect, showValues = false } = {}) {
  clear(host);
  const svg = s('svg', { viewBox: '0 0 200 420', class: 'suit', role: 'img', 'aria-label': t('tile.suit') });
  const defs = s('defs', {}, s('linearGradient', { id: 'suitGrad', x1: 0, y1: 0, x2: 0, y2: 1 },
    s('stop', { offset: '0%', 'stop-color': color, 'stop-opacity': 0.55 }), s('stop', { offset: '100%', 'stop-color': color, 'stop-opacity': 0.12 })));
  svg.append(defs);
  const body = s('g', { class: 'suit-body' });
  for (const [tag, attrs] of SILHOUETTE) body.append(s(tag, { ...attrs, fill: 'url(#suitGrad)', stroke: color, 'stroke-width': 1.2, 'stroke-opacity': 0.8 }));
  // visor
  body.append(s('ellipse', { cx: 100, cy: 40, rx: 16, ry: 12, class: 'visor' }));
  svg.append(body);

  // group params per body point
  const byPoint = {};
  for (const p of PARAMS) if (p.body) (byPoint[p.body] ||= []).push(p);
  for (const [key, list] of Object.entries(byPoint)) {
    const pt = BODY_POINTS[key]; if (!pt) continue;
    let worst = 'none'; const lines = [];
    for (const p of list) {
      const m = latest[p.id];
      if (!m || m.v == null) { lines.push(`${m?.locked ? '🔒 ' : '· '}${paramName(p, lang())}`); continue; }
      const ev = evaluate(p, m.v);
      if (ORDER[ev.status] > ORDER[worst]) worst = ev.status;
      lines.push(`${ev.status === 'ok' ? '●' : ev.status === 'warn' ? '▲' : '■'} ${paramName(p, lang())} — ${showValues ? `${m.v} ${p.unit}` : `${ev.score}/100`}`);
    }
    const g = s('g', { class: `pt pt-${worst}`, tabindex: 0 });
    if (worst === 'crit') g.append(s('circle', { cx: pt.x, cy: pt.y, r: 9, class: 'pulse', fill: STATUS_COLOR.crit }));
    g.append(s('circle', { cx: pt.x, cy: pt.y, r: 6, fill: STATUS_COLOR[worst], stroke: '#0b1426', 'stroke-width': 1.5 }));
    g.append(s('title', {}, `${t(pt.key)}\n${lines.join('\n')}`));
    if (onSelect) { g.style.cursor = 'pointer'; g.addEventListener('click', () => onSelect(key, list)); }
    svg.append(g);
  }
  host.append(svg);
}
