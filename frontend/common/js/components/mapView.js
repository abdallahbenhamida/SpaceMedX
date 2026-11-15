// =============================================================================
// Map view for measurement locations on three kinds of "map":
//   earth   — Leaflet + OpenStreetMap tiles (lat/lon)
//   station — schematic of a space station (module + x/y metres inside it)
//   moon    — selenographic lat/lon; south-polar azimuthal view when all points
//             are near the pole (lunar south pole bases), else equirectangular.
// points: [{ frame, lat, lon, module, x, y, label, color, status, time }]
// =============================================================================
import { s, h, clear } from '../ui.js';
import { t } from '../i18n.js';
import { STATUS_COLOR } from '../scoring.js';

const MODULES = [
  // schematic layout (x, y, w, h) in SVG units — not to scale
  { id: 'Zvezda', x: 40, y: 120, w: 90, h: 36 },
  { id: 'Zarya', x: 135, y: 122, w: 70, h: 32 },
  { id: 'Unity', x: 210, y: 118, w: 40, h: 40 },
  { id: 'Destiny', x: 255, y: 122, w: 90, h: 32 },
  { id: 'Harmony', x: 350, y: 118, w: 44, h: 40 },
  { id: 'Columbus', x: 399, y: 92, w: 30, h: 26, vertical: true },
  { id: 'Kibo', x: 399, y: 160, w: 80, h: 32 },
  { id: 'Tranquility', x: 210, y: 163, w: 40, h: 60 },
];

export function renderMap(host, { points = [], frame, onSelect } = {}) {
  clear(host);
  const frames = ['earth', 'station', 'moon'];
  const initial = frame || points[0]?.frame || 'earth';
  const bar = h('div', { class: 'seg map-tabs' });
  const view = h('div', { class: 'map-view' });
  const show = f => {
    bar.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('on', b.dataset.f === f));
    clear(view);
    const pts = points.filter(p => p.frame === f);
    if (f === 'earth') earth(view, pts, onSelect);
    else if (f === 'station') station(view, pts, onSelect);
    else moon(view, pts, onSelect);
  };
  frames.forEach(f => bar.append(h('button', { class: 'seg-btn', 'data-f': f, onclick: () => show(f) }, t('map.' + f), h('span', { class: 'count' }, points.filter(p => p.frame === f).length || ''))));
  host.append(bar, view);
  show(initial);
}

function tip(p) { return [p.label, p.sub, p.time].filter(Boolean).join('\n'); }

function earth(view, pts, onSelect) {
  const el = h('div', { class: 'leaflet-host' }); view.append(el);
  if (!window.L) { el.append(h('div', { class: 'muted pad' }, 'Leaflet not loaded')); return; }
  const map = window.L.map(el, { zoomControl: true, attributionControl: true, worldCopyJump: true });
  window.L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 18, attribution: '© OpenStreetMap contributors' }).addTo(map);
  const ll = pts.map(p => [p.lat, p.lon]);
  pts.forEach(p => {
    const icon = window.L.divIcon({ className: 'lf-icon', html: avatarIconHtml(p), iconSize: [34, 34], iconAnchor: [17, 17] });
    const m = window.L.marker([p.lat, p.lon], { icon, riseOnHover: true }).addTo(map).bindTooltip(escAttr(tip(p)).replace(/\n/g, '<br>'), { offset: [14, 0], direction: 'right' });
    if (onSelect) m.on('click', () => onSelect(p));
  });
  if (ll.length) map.fitBounds(ll, { maxZoom: 13, padding: [30, 30] }); else map.setView([47.5, 19.05], 3);
  setTimeout(() => map.invalidateSize(), 50);
  new ResizeObserver(() => map.invalidateSize()).observe(el);
}

let clipSeq = 0;
const initialsOf = p => String(p.label || p.short || '?').split(/\s+/).map(w => w[0]).join('').slice(0, 2).toUpperCase();

/** Round marker with the person's profile picture (or initials); ring colour = status. */
function marker(svg, x, y, p, onSelect, r = 8) {
  const g = s('g', { class: 'map-pt' });
  const id = `mclip${++clipSeq}`;
  g.append(s('defs', {}, s('clipPath', { id }, s('circle', { cx: x, cy: y, r }))));
  if (p.status === 'crit') g.append(s('circle', { cx: x, cy: y, r: r + 4, class: 'map-pulse', fill: STATUS_COLOR.crit }));
  g.append(s('circle', { cx: x, cy: y, r: r + 2.5, fill: STATUS_COLOR[p.status || 'none'] }));
  if (p.avatar) g.append(s('image', { href: p.avatar, x: x - r, y: y - r, width: r * 2, height: r * 2, 'clip-path': `url(#${id})`, preserveAspectRatio: 'xMidYMid slice' }));
  else {
    g.append(s('circle', { cx: x, cy: y, r, fill: p.color || '#4fc3f7' }));
    g.append(s('text', { x, y: y + r * 0.36, class: 'map-ini', 'text-anchor': 'middle', 'font-size': r * 0.95 }, initialsOf(p)));
  }
  if (p.short) g.append(s('text', { x: x + r + 6, y: y + 4, class: 'map-lbl' }, p.short));
  g.append(s('title', {}, tip(p)));
  if (onSelect) { g.style.cursor = 'pointer'; g.addEventListener('click', () => onSelect(p)); }
  svg.append(g);
}

function avatarIconHtml(p, size = 34) {
  const ring = STATUS_COLOR[p.status || 'none'];
  const inner = p.avatar
    ? `<img src="${escAttr(p.avatar)}" alt="">`
    : `<span style="background:${escAttr(p.color || '#4fc3f7')}">${escAttr(initialsOf(p))}</span>`;
  return `<div class="lf-avatar ${p.status === 'crit' ? 'crit' : ''}" style="width:${size}px;height:${size}px;border-color:${ring}">${inner}</div>`;
}
function escAttr(t) { return String(t ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

function station(view, pts, onSelect) {
  const svg = s('svg', { viewBox: '0 0 520 300', class: 'station-map' });
  svg.append(s('rect', { x: 20, y: 56, width: 480, height: 6, class: 'truss' }));
  [40, 120, 400, 480].forEach(x => { svg.append(s('rect', { x: x - 30, y: 12, width: 60, height: 40, class: 'panel' })); });
  svg.append(s('line', { x1: 230, y1: 62, x2: 230, y2: 118, class: 'truss-line' }));
  for (const m of MODULES) {
    svg.append(s('rect', { x: m.x, y: m.y, width: m.w, height: m.h, rx: 10, class: 'module' }));
    svg.append(s('text', { x: m.x + m.w / 2, y: m.y + m.h + 12, class: 'module-lbl', 'text-anchor': 'middle' }, m.id));
  }
  // people in the same module are spread along it (positions are schematic)
  const byModule = {};
  pts.forEach(p => (byModule[p.module] ||= []).push(p));
  for (const [mod, list] of Object.entries(byModule)) {
    const m = MODULES.find(mm => mm.id === mod) || MODULES[3];
    list.forEach((p, k) => {
      const n = list.length, horiz = m.w >= m.h;
      const off = n === 1 ? 0 : (k / (n - 1) - 0.5) * (horiz ? Math.min(m.w - 16, n * 20) : Math.min(m.h - 16, n * 20));
      const x = m.x + m.w / 2 + (horiz ? off : 0), y = m.y + m.h / 2 + (horiz ? (k % 2 ? 9 : -9) * (n > 2) : off);
      marker(svg, x, y, { ...p, short: '' }, onSelect, 9);
    });
  }
  svg.append(s('text', { x: 10, y: 292, class: 'muted-svg' }, t('map.stationNote')));
  view.append(svg);
  // legend: who is where (names would overlap inside the small modules)
  if (pts.length) view.append(h('div', { class: 'map-legend' }, pts.map(p => h('button', { class: 'ml-item', onclick: () => onSelect?.(p), title: tip(p) },
    p.avatar ? h('img', { src: p.avatar, alt: '', style: { borderColor: STATUS_COLOR[p.status || 'none'] } }) : h('span', { class: 'ml-ini', style: { background: p.color, borderColor: STATUS_COLOR[p.status || 'none'] } }, initialsOf(p)),
    h('span', {}, p.label?.split(' (')[0] || p.short), h('small', {}, p.module || '')))));
}

// ---- Moon: 2D map with semantic zoom → 3D globe ------------------------------------
// Scroll / "−" zooms out of the 2D map; past the widest 2D view the Moon turns
// into a rotatable 3D globe. Zooming in close to the globe's surface (or the
// "2D" button) returns to the detailed 2D map.
const POLAR_MAX_SPAN = 30; // widest azimuthal 2D view (degrees from the pole)

function moon(view, pts, onSelect) {
  const polar = pts.length && pts.every(p => Math.abs(p.lat) > 80);
  const fitSpan = polar ? Math.min(10, Math.max(0.5, Math.max(...pts.map(p => 90 - Math.abs(p.lat))) * 1.5)) : null;
  const st = { mode: '2d', span: fitSpan };
  const wrap = h('div', { class: 'moon-wrap' });
  const stage = h('div', { class: 'moon-stage' });
  const bar = h('div', { class: 'map-zoom' });
  wrap.append(stage, bar);
  view.append(wrap);

  const toGlobe = () => { st.mode = 'globe'; draw(); };
  const to2d = span => { st.mode = '2d'; if (polar) st.span = span ?? POLAR_MAX_SPAN; draw(); };
  const zoom = dir => { // dir > 0: zoom out
    if (st.mode === 'globe') return;
    if (!polar) { if (dir > 0) toGlobe(); return; }
    const next = dir > 0 ? st.span * 1.3 : st.span / 1.3;
    if (next > POLAR_MAX_SPAN) return toGlobe();
    st.span = Math.max(0.2, next); draw();
  };

  function draw() {
    clear(stage); clear(bar);
    if (st.mode === 'globe') {
      bar.append(h('button', { class: 'btn sm', onclick: () => to2d(fitSpan ?? null) }, '▦ ' + t('map.view2d')), h('span', { class: 'muted small' }, t('map.globeHint')));
      import('./moonGlobe.js').then(({ renderMoonGlobe }) => {
        if (st.mode !== 'globe') return;
        try { renderMoonGlobe(stage, { points: pts, onSelect, onZoomIn: () => to2d(POLAR_MAX_SPAN), labels: { north: t('map.northPole'), south: t('map.southPole') } }); }
        catch (e) { stage.append(h('p', { class: 'muted pad' }, 'WebGL: ' + e.message)); }
      }).catch(e => stage.append(h('p', { class: 'muted pad' }, e.message)));
      return;
    }
    bar.append(
      h('button', { class: 'btn sm', title: t('map.zoomIn'), onclick: () => zoom(-1), disabled: !polar }, '+'),
      h('button', { class: 'btn sm', title: t('map.zoomOut'), onclick: () => zoom(1) }, '−'),
      h('button', { class: 'btn sm', onclick: toGlobe }, '🌐 ' + t('map.view3d')),
      h('span', { class: 'muted small' }, t('map.zoomHint')));
    const svg = polar ? moonPolar(pts, st.span, onSelect) : moonFlat(pts, onSelect);
    svg.addEventListener('wheel', e => { e.preventDefault(); zoom(e.deltaY > 0 ? 1 : -1); }, { passive: false });
    stage.append(svg);
    if (svg.dataset.caption) stage.append(h('div', { class: 'map-caption' }, svg.dataset.caption));
  }
  draw();
}

function moonPolar(pts, span, onSelect) {
  const svg = s('svg', { viewBox: '0 0 520 320', class: 'moon-map' });
  let seed = 7 + Math.round(Math.log2(span) * 3); const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const cx = 260, cy = 160, R = 140;
  const south = pts[0].lat < 0;
  const proj = (lat, lon) => { const d = (90 - Math.abs(lat)) / span * R; const a = (lon * Math.PI) / 180; return [cx + d * Math.sin(a), cy + (south ? -1 : 1) * d * Math.cos(a)]; };
  svg.append(s('circle', { cx, cy, r: R, class: 'moon-surface' }));
  for (let i = 0; i < 70; i++) { const r = Math.sqrt(rnd()) * R * 0.95, a = rnd() * Math.PI * 2; svg.append(s('circle', { cx: cx + r * Math.cos(a), cy: cy + r * Math.sin(a), r: 2 + rnd() * 9, class: 'crater' })); }
  const dec = span < 2 ? 2 : span < 10 ? 1 : 0;
  [0.25, 0.5, 0.75, 1].forEach(f => { svg.append(s('circle', { cx, cy, r: f * R, class: 'grid' })); svg.append(s('text', { x: cx + 3, y: cy - f * R + 11, class: 'grid-lbl' }, `${((south ? -1 : 1) * (90 - f * span)).toFixed(dec)}°`)); });
  for (let lon = 0; lon < 360; lon += 30) { const [x, y] = proj(south ? -(90 - span) : 90 - span, lon); svg.append(s('line', { x1: cx, y1: cy, x2: x, y2: y, class: 'grid' })); svg.append(s('text', { x: cx + (x - cx) * 1.08, y: cy + (y - cy) * 1.08 + 3, class: 'grid-lbl', 'text-anchor': 'middle' }, `${lon > 180 ? lon - 360 : lon}°`)); }
  // Shackleton crater (~21 km ≈ 0.7°) at the pole
  svg.append(s('circle', { cx, cy, r: (0.35 / span) * R + 3, class: 'crater named' }));
  svg.append(s('text', { x: cx + 10, y: cy - 8, class: 'map-lbl dim' }, 'Shackleton'));
  pts.forEach(p => { const [x, y] = proj(p.lat, p.lon); marker(svg, x, y, p, onSelect); });
  svg.dataset.caption = t(south ? 'map.moonSouth' : 'map.moonNorth', { r: span.toFixed(dec) });
  return svg;
}

function moonFlat(pts, onSelect) {
  const svg = s('svg', { viewBox: '0 0 520 320', class: 'moon-map' });
  let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const proj = (lat, lon) => [20 + ((lon + 180) / 360) * 480, 20 + ((90 - lat) / 180) * 280];
  svg.append(s('rect', { x: 20, y: 20, width: 480, height: 280, class: 'moon-surface' }));
  for (let i = 0; i < 120; i++) svg.append(s('circle', { cx: 20 + rnd() * 480, cy: 20 + rnd() * 280, r: 1.5 + rnd() * 7, class: 'crater' }));
  for (let lat = -60; lat <= 60; lat += 30) { const [, y] = proj(lat, 0); svg.append(s('line', { x1: 20, y1: y, x2: 500, y2: y, class: 'grid' })); }
  for (let lon = -150; lon <= 150; lon += 30) { const [x] = proj(0, lon); svg.append(s('line', { x1: x, y1: 20, x2: x, y2: 300, class: 'grid' })); }
  const [ax, ay] = proj(0.674, 23.473); svg.append(s('text', { x: ax + 6, y: ay - 6, class: 'map-lbl dim' }, 'Apollo 11'));
  svg.append(s('circle', { cx: ax, cy: ay, r: 2, class: 'site' }));
  pts.forEach(p => { const [x, y] = proj(p.lat, p.lon); marker(svg, x, y, p, onSelect); });
  return svg;
}
