// =============================================================================
// Charts: trend (scale-independent, coloured bands), readiness gauge,
// ECG strip (physician view).
// =============================================================================
import { s, h, clear } from '../ui.js';
import { normalize, evaluate, STATUS_COLOR, BANDS } from '../scoring.js';
import { formatTime, parseTime } from '../time.js';
import { t, lang } from '../i18n.js';

/**
 * Trend line. Y axis is the normalised 0..1 scale so every parameter looks
 * the same to a non-medical viewer; physicians get real-unit tick labels.
 */
export function trendChart(host, { param, samples = [], showValues = false, height = 160, sourceZone } = {}) {
  clear(host);
  const W = 520, H = height, L = showValues ? 46 : 14, Rp = 10, T = 8, B = 20;
  const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, class: 'trend', preserveAspectRatio: 'none' });
  const y = f => T + (H - T - B) * (1 - f);
  const bands = [
    [0, normalize(param, param.warn[0]), 'crit'], [normalize(param, param.warn[0]), normalize(param, param.ok[0]), 'warn'],
    [normalize(param, param.ok[0]), normalize(param, param.ok[1]), 'ok'], [normalize(param, param.ok[1]), normalize(param, param.warn[1]), 'warn'],
    [normalize(param, param.warn[1]), 1, 'crit'],
  ];
  for (const [a, b, st] of bands) if (b - a > 0.002) svg.append(s('rect', { x: L, y: y(b), width: W - L - Rp, height: y(a) - y(b), fill: STATUS_COLOR[st], opacity: st === 'ok' ? 0.10 : 0.08 }));
  if (showValues) {
    for (const v of [param.warn[0], param.ok[0], param.ok[1], param.warn[1]]) {
      const f = normalize(param, v); if (f <= 0.001 || f >= 0.999) continue;
      svg.append(s('text', { x: L - 4, y: y(f) + 3, class: 'tick', 'text-anchor': 'end' }, v));
    }
  }
  const pts = samples.filter(p => p.v != null).map(p => ({ t: parseTime(p.t).getTime(), v: p.v }));
  if (pts.length) {
    const t0 = pts[0].t, t1 = pts[pts.length - 1].t || t0 + 1;
    const x = tt => L + (W - L - Rp) * ((tt - t0) / (t1 - t0 || 1));
    const d = pts.map((p, i) => `${i ? 'L' : 'M'}${x(p.t).toFixed(1)},${y(normalize(param, p.v)).toFixed(1)}`).join(' ');
    svg.append(s('path', { d, class: 'trend-line' }));
    pts.forEach(p => { const st = evaluate(param, p.v).status; if (st !== 'ok') svg.append(s('circle', { cx: x(p.t), cy: y(normalize(param, p.v)), r: 2.4, fill: STATUS_COLOR[st] })); });
    const last = pts[pts.length - 1], ev = evaluate(param, last.v);
    svg.append(s('circle', { cx: x(last.t), cy: y(ev.pos), r: 4.5, fill: STATUS_COLOR[ev.status], stroke: '#0b1426', 'stroke-width': 1.5 }));
    svg.append(s('text', { x: L, y: H - 5, class: 'tick' }, formatTime(t0, { lang: lang(), withDate: true })));
    svg.append(s('text', { x: W - Rp, y: H - 5, class: 'tick', 'text-anchor': 'end' }, formatTime(t1, { lang: lang(), withDate: true }) + (sourceZone ? '' : '')));
  } else svg.append(s('text', { x: W / 2, y: H / 2, class: 'tick', 'text-anchor': 'middle' }, t('common.noData')));
  host.append(svg);
}

/** Circular readiness gauge 0..100 */
export function gauge(host, { value, status = 'none', label, size = 160 }) {
  clear(host);
  const r = 62, c = 2 * Math.PI * r, f = value == null ? 0 : value / 100;
  const svg = s('svg', { viewBox: '0 0 160 160', width: size, height: size, class: 'gauge' },
    s('circle', { cx: 80, cy: 80, r, class: 'gauge-bg' }),
    s('circle', { cx: 80, cy: 80, r, class: 'gauge-fg', stroke: STATUS_COLOR[status], 'stroke-dasharray': `${c * f} ${c}`, transform: 'rotate(-90 80 80)' }),
    s('text', { x: 80, y: 84, class: 'gauge-v', 'text-anchor': 'middle', 'dominant-baseline': 'middle' }, value ?? '–'),
    label ? s('text', { x: 80, y: 108, class: 'gauge-l', 'text-anchor': 'middle' }, label) : null);
  host.append(svg);
}

/** ECG strip on "paper" grid (physician only). */
export function ecgChart(host, wave) {
  clear(host);
  const cv = h('canvas', { class: 'ecg' }); host.append(cv);
  const draw = () => {
    const w = host.clientWidth || 600, hh = 180, dpr = window.devicePixelRatio || 1;
    cv.width = w * dpr; cv.height = hh * dpr; cv.style.width = w + 'px'; cv.style.height = hh + 'px';
    const g = cv.getContext('2d'); g.scale(dpr, dpr);
    g.fillStyle = '#081221'; g.fillRect(0, 0, w, hh);
    const sec = 10, pxPerSec = w / sec, small = pxPerSec / 25;
    for (let x = 0, i = 0; x < w; x += small, i++) { g.strokeStyle = i % 5 ? 'rgba(255,90,90,0.10)' : 'rgba(255,90,90,0.28)'; g.beginPath(); g.moveTo(x, 0); g.lineTo(x, hh); g.stroke(); }
    for (let y = 0, i = 0; y < hh; y += small, i++) { g.strokeStyle = i % 5 ? 'rgba(255,90,90,0.10)' : 'rgba(255,90,90,0.28)'; g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke(); }
    if (!wave?.values?.length) return;
    const mvPx = small * 10; // 10 mm/mV
    g.strokeStyle = '#7CFFB2'; g.lineWidth = 1.4; g.beginPath();
    wave.values.forEach((v, i) => { const x = (i / wave.sampleRate) * pxPerSec, y = hh * 0.62 - v * mvPx; i ? g.lineTo(x, y) : g.moveTo(x, y); });
    g.stroke();
    g.fillStyle = '#9fb3d1'; g.font = '11px system-ui'; g.fillText(`25 mm/s · 10 mm/mV · ${wave.sampleRate} Hz`, 8, 14);
  };
  draw();
  new ResizeObserver(draw).observe(host);
}

export { BANDS };
