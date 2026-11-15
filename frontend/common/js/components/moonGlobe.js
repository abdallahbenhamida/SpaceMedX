// =============================================================================
// Moon globe (Three.js) — rotatable 3D Moon with the measurement points.
// Shown by mapView when the user zooms out of the 2D lunar map; zooming back
// in close to the surface returns to the 2D map (onZoomIn callback).
// Texture is procedural (maria + craters) — no external image needed.
// =============================================================================
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/OrbitControls.js';
import { CSS2DRenderer, CSS2DObject } from 'three/addons/CSS2DRenderer.js';
import { STATUS_COLOR } from '../scoring.js';

const R = 5;

/** lat/lon (deg, selenographic) → position on the sphere */
export function latLonToVec(lat, lon, r = R) {
  const p = (lat * Math.PI) / 180, l = (lon * Math.PI) / 180;
  return new THREE.Vector3(r * Math.cos(p) * Math.cos(l), r * Math.sin(p), -r * Math.cos(p) * Math.sin(l));
}

const TEXTURE_URL = new URL('../../vendor/textures/moon_2k.jpg', import.meta.url).href;
let realTexture = null;
/** Real Moon map (NASA imagery, equirectangular, lon 0 at the centre). */
function loadRealTexture(onReady, onFail) {
  if (realTexture) { onReady(realTexture); return; }
  new THREE.TextureLoader().load(TEXTURE_URL, tex => {
    tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 8;
    realTexture = tex; onReady(tex);
  }, undefined, onFail);
}

// Real, well-known lunar features (selenographic lat, lon in degrees).
export const LUNAR_FEATURES = [
  { name: 'Tycho', lat: -43.31, lon: -11.36 }, { name: 'Copernicus', lat: 9.62, lon: -20.08 },
  { name: 'Kepler', lat: 8.12, lon: -38.01 }, { name: 'Aristarchus', lat: 23.7, lon: -47.4 },
  { name: 'Plato', lat: 51.6, lon: -9.4 }, { name: 'Clavius', lat: -58.8, lon: -14.1 },
  { name: 'Grimaldi', lat: -5.2, lon: -68.6 }, { name: 'Langrenus', lat: -8.9, lon: 60.9 },
  { name: 'Theophilus', lat: -11.4, lon: 26.4 }, { name: 'Ptolemaeus', lat: -9.2, lon: -1.8 },
  { name: 'Shackleton', lat: -89.67, lon: 129.78 }, { name: 'Tsiolkovskiy', lat: -20.4, lon: 129.1 },
  { name: 'Mare Imbrium', lat: 32.8, lon: -15.6, mare: true }, { name: 'Mare Serenitatis', lat: 28.0, lon: 17.5, mare: true },
  { name: 'Mare Tranquillitatis', lat: 8.5, lon: 31.4, mare: true }, { name: 'Mare Crisium', lat: 17.0, lon: 59.1, mare: true },
  { name: 'Oceanus Procellarum', lat: 18.4, lon: -57.4, mare: true }, { name: 'Mare Nubium', lat: -21.3, lon: -16.6, mare: true },
  { name: 'Mare Fecunditatis', lat: -7.8, lon: 51.3, mare: true }, { name: 'Mare Moscoviense', lat: 27.3, lon: 147.9, mare: true },
  { name: 'South Pole–Aitken basin', lat: -53, lon: -169, mare: true },
  { name: 'Apollo 11', lat: 0.674, lon: 23.473, site: true }, { name: 'Apollo 17', lat: 20.19, lon: 30.77, site: true },
];

let cachedTexture = null;
/** Procedural fallback, used only if the image cannot be loaded. */
function moonTexture() {
  if (cachedTexture) return cachedTexture;
  const W = 2048, H = 1024;
  const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
  const g = cv.getContext('2d');
  let seed = 11; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  g.fillStyle = '#9a9a96'; g.fillRect(0, 0, W, H);
  // fine grain
  const img = g.getImageData(0, 0, W, H);
  for (let i = 0; i < img.data.length; i += 4) { const n = (rnd() - 0.5) * 26; img.data[i] += n; img.data[i + 1] += n; img.data[i + 2] += n; }
  g.putImageData(img, 0, 0);
  const xy = (lat, lon) => [((lon + 180) / 360) * W, ((90 - lat) / 180) * H];
  // dark maria (rough, near-side positions)
  const maria = [[28, -17, 260, 180], [8, 31, 150, 110], [17, 59, 110, 80], [-21, -16, 120, 90], [-7, 35, 90, 70], [-4, 51, 70, 60], [20, -2, 100, 70], [-24, -40, 80, 60], [33, 18, 110, 90]];
  for (const [lat, lon, rx, ry] of maria) {
    const [x, y] = xy(lat, lon);
    const gr = g.createRadialGradient(x, y, 0, x, y, rx);
    gr.addColorStop(0, 'rgba(55,55,58,0.85)'); gr.addColorStop(0.7, 'rgba(65,65,68,0.55)'); gr.addColorStop(1, 'rgba(80,80,80,0)');
    g.fillStyle = gr; g.beginPath(); g.ellipse(x, y, rx, ry, rnd() * Math.PI, 0, Math.PI * 2); g.fill();
  }
  // craters (stretched horizontally towards the poles in equirectangular space)
  for (let i = 0; i < 1100; i++) {
    const lat = Math.asin(rnd() * 2 - 1) * 180 / Math.PI, lon = rnd() * 360 - 180;
    const [x, y] = xy(lat, lon);
    const r = Math.pow(rnd(), 4.5) * 34 + 1.2, sx = 1 / Math.max(0.15, Math.cos((lat * Math.PI) / 180));
    g.save(); g.translate(x, y); g.scale(sx, 1);
    g.fillStyle = `rgba(45,45,45,${0.06 + rnd() * 0.14})`; g.beginPath(); g.arc(0, 0, r, 0, Math.PI * 2); g.fill();
    g.strokeStyle = `rgba(235,235,230,${0.10 + rnd() * 0.2})`; g.lineWidth = Math.max(1, r * 0.18); g.beginPath(); g.arc(-r * 0.12, -r * 0.12, r, Math.PI * 0.9, Math.PI * 1.9); g.stroke();
    g.restore();
  }
  // Shackleton (south pole) and Tycho-like bright crater
  g.fillStyle = 'rgba(25,25,25,0.6)'; g.fillRect(0, H - 6, W, 6);
  const [tx, ty] = xy(-43.3, -11.2); g.fillStyle = 'rgba(245,245,240,0.55)'; g.beginPath(); g.arc(tx, ty, 9, 0, Math.PI * 2); g.fill();
  cachedTexture = new THREE.CanvasTexture(cv);
  cachedTexture.colorSpace = THREE.SRGBColorSpace;
  cachedTexture.anisotropy = 4;
  return cachedTexture;
}

/**
 * @param {HTMLElement} host
 * @param {object} opts { points, onSelect(p), onZoomIn(), labels }
 */
export function renderMoonGlobe(host, { points = [], onSelect, onZoomIn, labels = {} } = {}) {
  host.style.position = 'relative';
  const w = host.clientWidth || 600, h = host.clientHeight || 420;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio)); renderer.setSize(w, h);
  renderer.domElement.style.display = 'block';
  host.append(renderer.domElement);
  const css = new CSS2DRenderer(); css.setSize(w, h);
  Object.assign(css.domElement.style, { position: 'absolute', inset: '0', pointerEvents: 'none' });
  host.append(css.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, w / h, 0.1, 200);
  // Look at the points first (south pole for a lunar south-pole base)
  // (latitude clamped to ±65° so the camera never sits exactly on the pole axis)
  const fLat = points.length ? points.reduce((a, p) => a + p.lat, 0) / points.length : -30;
  const fLon = points.length ? points.reduce((a, p) => a + p.lon, 0) / points.length : 0;
  camera.position.copy(latLonToVec(Math.max(-65, Math.min(65, fLat)), fLon, 17));
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true; controls.enablePan = false;
  controls.minDistance = R * 1.12; controls.maxDistance = R * 6;
  controls.rotateSpeed = 0.6;

  scene.add(new THREE.AmbientLight(0xffffff, 0.55));
  const sun = new THREE.DirectionalLight(0xffffff, 1.9); scene.add(sun);
  const mat = new THREE.MeshStandardMaterial({ color: 0x888888, roughness: 1, metalness: 0 });
  const moon = new THREE.Mesh(new THREE.SphereGeometry(R, 256, 128), mat);
  scene.add(moon);
  loadRealTexture(tex => {
    // the albedo map doubles as a bump map → crater rims catch the low sun
    mat.map = tex; mat.bumpMap = tex; mat.bumpScale = 2.2; mat.color.set(0xffffff); mat.needsUpdate = true;
  }, () => { mat.map = moonTexture(); mat.color.set(0xffffff); mat.needsUpdate = true; });

  // graticule
  const gratMat = new THREE.LineBasicMaterial({ color: 0x8fb8ff, transparent: true, opacity: 0.18 });
  for (let lat = -60; lat <= 60; lat += 30) {
    const pts = []; for (let lon = -180; lon <= 180; lon += 4) pts.push(latLonToVec(lat, lon, R * 1.002));
    scene.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), gratMat));
  }
  for (let lon = -180; lon < 180; lon += 30) {
    const pts = []; for (let lat = -90; lat <= 90; lat += 4) pts.push(latLonToVec(lat, lon, R * 1.002));
    scene.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), gratMat));
  }
  // pole labels
  const label = (txt, pos, cls = 'globe-lbl') => { const el = document.createElement('div'); el.className = cls; el.textContent = txt; const o = new CSS2DObject(el); o.position.copy(pos); scene.add(o); return o; };
  const poleEls = [[label(labels.north || 'N', new THREE.Vector3(0, R * 1.08, 0), 'globe-lbl pole'), new THREE.Vector3(0, 1, 0)],
    [label(labels.south || 'S', new THREE.Vector3(0, -R * 1.08, 0), 'globe-lbl pole'), new THREE.Vector3(0, -1, 0)]];
  const featureEls = LUNAR_FEATURES.map(f => {
    const obj = label(f.name, latLonToVec(f.lat, f.lon, R * 1.003), `globe-feat ${f.mare ? 'mare' : f.site ? 'site' : 'crater'}`);
    return { obj, el: obj.element, dir: latLonToVec(f.lat, f.lon, 1), mare: f.mare };
  });

  // markers
  const pickables = [];
  points.forEach(p => {
    const pos = latLonToVec(p.lat, p.lon, R * 1.01);
    const m = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 12), new THREE.MeshBasicMaterial({ color: STATUS_COLOR[p.status || 'none'] }));
    m.position.copy(pos); m.userData.point = p; scene.add(m); pickables.push(m);
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.11, 0.15, 24), new THREE.MeshBasicMaterial({ color: new THREE.Color(p.color || '#ffffff'), side: THREE.DoubleSide }));
    ring.position.copy(pos); ring.lookAt(pos.clone().multiplyScalar(2)); scene.add(ring);
  });
  // labels: points closer than ~2° share one label (e.g. all members of one base)
  const groups = [];
  points.forEach(p => {
    const v = latLonToVec(p.lat, p.lon, 1);
    const g = groups.find(gr => gr.dir.angleTo(v) < 0.035);
    if (g) { g.items.push(p); g.dir.add(v).normalize(); } else groups.push({ dir: v.clone(), items: [p] });
  });
  const labelled = groups.map(g => {
    const el = document.createElement('div'); el.className = 'globe-pt';
    const first = g.items[0];
    const faces = g.items.slice(0, 6).map(p => avatarHtml(p)).join('');
    const more = g.items.length > 6 ? `<b>+${g.items.length - 6}</b>` : '';
    const name = g.items.length > 1 ? (first.group || first.short) : (first.short || first.label || '');
    el.innerHTML = `<span class="faces">${faces}${more}</span><span class="nm">${esc(name)}</span>`;
    el.style.pointerEvents = 'auto'; el.style.cursor = 'pointer';
    el.addEventListener('click', () => onSelect?.(first));
    el.title = g.items.map(p => [p.label, p.sub].filter(Boolean).join(' — ')).join('\n');
    const o = new CSS2DObject(el); o.position.copy(g.dir.clone().multiplyScalar(R * 1.04)); scene.add(o);
    return { obj: o, pos: g.dir.clone() };
  });


  // picking
  const ray = new THREE.Raycaster(), mouse = new THREE.Vector2(); let down = null;
  renderer.domElement.addEventListener('pointerdown', e => { down = [e.clientX, e.clientY]; });
  renderer.domElement.addEventListener('pointerup', e => {
    if (!down || Math.hypot(e.clientX - down[0], e.clientY - down[1]) > 5) return;
    const r = renderer.domElement.getBoundingClientRect();
    mouse.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(mouse, camera);
    const hit = ray.intersectObjects(pickables)[0];
    if (hit && onSelect) onSelect(hit.object.userData.point);
  });

  // zooming in close to the surface → back to the detailed 2D map
  let switched = false;
  renderer.domElement.addEventListener('wheel', e => {
    if (switched || e.deltaY >= 0) return;
    if (camera.position.length() <= controls.minDistance * 1.02 && onZoomIn) { switched = true; onZoomIn(); }
  }, { passive: true });

  let raf = 0;
  const loop = () => {
    raf = requestAnimationFrame(loop);
    controls.update();
    // low, oblique sun relative to the viewer so crater relief is visible
    const right = new THREE.Vector3().crossVectors(camera.position, camera.up).normalize();
    sun.position.copy(camera.position).add(right.multiplyScalar(camera.position.length() * 1.1)).add(camera.up.clone().multiplyScalar(4));
    // hide labels on the far side
    const camDir = camera.position.clone().normalize();
    const horizon = R / camera.position.length(); // cos of the visible cap's half-angle
    labelled.forEach(l => { l.obj.visible = l.pos.dot(camDir) > horizon + 0.02; });
    poleEls.forEach(([o, d]) => { o.visible = d.dot(camDir) > horizon - 0.05; });
    const near = camera.position.length() < R * 3.2;
    featureEls.forEach(f => { const facing = f.dir.dot(camDir), th = horizon + 0.12; f.obj.visible = facing > th && (near || f.mare); f.el.style.opacity = Math.min(1, (facing - th) * 4); });
    renderer.render(scene, camera); css.render(scene, camera);
  };
  loop();
  const ro = new ResizeObserver(() => { const W = host.clientWidth, H = host.clientHeight; if (!W || !H) return; camera.aspect = W / H; camera.updateProjectionMatrix(); renderer.setSize(W, H); css.setSize(W, H); });
  ro.observe(host);

  const dispose = () => { cancelAnimationFrame(raf); ro.disconnect(); controls.dispose(); renderer.dispose(); scene.traverse(o => { o.geometry?.dispose?.(); if (o.material) o.material.dispose?.(); }); };
  // auto-dispose when removed from the DOM
  const mo = new MutationObserver(() => { if (!renderer.domElement.isConnected) { dispose(); mo.disconnect(); } });
  mo.observe(document.body, { childList: true, subtree: true });
  return { dispose };
}

function esc(t) { return String(t ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
function avatarHtml(p) {
  const ring = `border-color:${STATUS_COLOR[p.status || 'none']}`;
  if (p.avatar) return `<img class="gface" style="${ring}" src="${esc(p.avatar)}" alt="${esc(p.label)}">`;
  const ini = String(p.label || p.short || '?').split(/\s+/).map(w => w[0]).join('').slice(0, 2).toUpperCase();
  return `<span class="gface" style="${ring};background:${esc(p.color || '#4fc3f7')}">${esc(ini)}</span>`;
}
