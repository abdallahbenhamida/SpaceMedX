// =============================================================================
// 3D stacked disks (Three.js) — after the "anim1_avg_pop" reference video.
// Every layer is one disk (a team member, or a team average / overall average
// at Ground Control). Each parameter is a radial bar whose length is the
// normalised value and whose colour is its status. A layer can be selected
// (click on it or via setSelected) — the others fade out so it can be examined;
// the gap between layers can be changed (stack ↔ exploded).
// =============================================================================
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/OrbitControls.js';
import { CSS2DRenderer, CSS2DObject } from 'three/addons/CSS2DRenderer.js';
import { SECTORS, DISK_PARAMS } from '../params.js';
import { evaluate, STATUS_COLOR } from '../scoring.js';
import { paramAngles } from './diskChart.js';

const R = 10, R0 = 2;
const COLORS = Object.fromEntries(Object.entries(STATUS_COLOR).map(([k, v]) => [k, new THREE.Color(v)]));

export class Disk3D {
  /**
   * @param {HTMLElement} host
   * @param {object} opts  onSelect(index|null), showSectorLabels
   */
  constructor(host, opts = {}) {
    this.host = host; this.opts = opts;
    this.layers = []; this.selected = null; this.gap = 2.2;
    this.params = DISK_PARAMS;
    this.angles = paramAngles(this.params);

    const w = host.clientWidth || 600, hgt = host.clientHeight || 420;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
    this.renderer.setSize(w, hgt);
    host.append(this.renderer.domElement);
    this.labels = new CSS2DRenderer();
    this.labels.setSize(w, hgt);
    Object.assign(this.labels.domElement.style, { position: 'absolute', inset: '0', pointerEvents: 'none' });
    host.style.position = 'relative';
    host.append(this.labels.domElement);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(42, w / hgt, 0.1, 500);
    this.camera.position.set(19, 15, 23);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.target.set(0, 4, 0);
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.9));
    const dl = new THREE.DirectionalLight(0xffffff, 0.8); dl.position.set(10, 20, 10); this.scene.add(dl);

    this.root = new THREE.Group(); this.scene.add(this.root);
    this.ray = new THREE.Raycaster(); this.mouse = new THREE.Vector2();
    this._down = null;
    this.renderer.domElement.addEventListener('pointerdown', e => { this._down = [e.clientX, e.clientY]; });
    this.renderer.domElement.addEventListener('pointerup', e => {
      if (!this._down || Math.hypot(e.clientX - this._down[0], e.clientY - this._down[1]) > 5) return;
      this.pick(e);
    });
    this.ro = new ResizeObserver(() => this.resize()); this.ro.observe(host);
    this._raf = 0; const loop = () => { this._raf = requestAnimationFrame(loop); this.tick(); }; loop();
  }

  resize() {
    const w = this.host.clientWidth, h = this.host.clientHeight; if (!w || !h) return;
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h); this.labels.setSize(w, h);
  }

  /** layers: [{ id, name, color, latest, badge }] */
  setLayers(layers) {
    for (const L of this.layers) { L.group.traverse(o => { o.geometry?.dispose?.(); o.material?.dispose?.(); if (o.isCSS2DObject) o.element.remove(); }); this.root.remove(L.group); }
    this.layers = layers.map((d, i) => this.buildLayer(d, i));
    if (this.selected != null && this.selected >= this.layers.length) this.selected = null;
    this.layout(true); this.applySelection();
  }

  buildLayer(d, index) {
    const group = new THREE.Group(); group.userData.index = index;
    const tint = new THREE.Color(d.color || '#4fc3f7');
    // translucent dodecagon plate (pick target)
    const plate = new THREE.Mesh(new THREE.CircleGeometry(R + 0.6, 12, Math.PI / 12), new THREE.MeshBasicMaterial({ color: tint, transparent: true, opacity: 0.08, side: THREE.DoubleSide, depthWrite: false }));
    plate.rotation.x = -Math.PI / 2; plate.userData.pick = index; group.add(plate);
    // rings
    const ringMat = new THREE.LineBasicMaterial({ color: 0x8aa4c8, transparent: true, opacity: 0.35 });
    for (let k = 1; k <= 5; k++) {
      const r = R0 + ((R - R0) * k) / 5;
      const pts = Array.from({ length: 13 }, (_, i) => { const a = ((-90 + i * 30 + 15) * Math.PI) / 180; return new THREE.Vector3(r * Math.cos(a), 0, r * Math.sin(a)); });
      group.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), ringMat));
    }
    // spokes (sector borders)
    const spokePts = [];
    for (let i = 0; i < 12; i++) { const a = ((-90 + i * 30 + 15) * Math.PI) / 180; spokePts.push(new THREE.Vector3(R0 * 0.5 * Math.cos(a), 0, R0 * 0.5 * Math.sin(a)), new THREE.Vector3(R * Math.cos(a), 0, R * Math.sin(a))); }
    group.add(new THREE.LineSegments(new THREE.BufferGeometry().setFromPoints(spokePts), ringMat));
    // green inner ring (as in the reference)
    const inner = new THREE.Mesh(new THREE.RingGeometry(R0 - 0.15, R0 + 0.15, 48), new THREE.MeshBasicMaterial({ color: COLORS.ok, side: THREE.DoubleSide, transparent: true, opacity: 0.8 }));
    inner.rotation.x = -Math.PI / 2; group.add(inner);
    // parameter bars
    for (const p of this.params) {
      const m = d.latest?.[p.id]; if (!m || m.v == null) continue;
      const ev = evaluate(p, m.v);
      const len = Math.max(0.25, (R - R0) * ev.pos);
      const geo = new THREE.BoxGeometry(len, 0.12, 0.16); geo.translate(len / 2, 0, 0);
      const bar = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color: COLORS[ev.status], transparent: true, opacity: 0.95 }));
      const a = (this.angles[p.id] * Math.PI) / 180;
      bar.position.set(R0 * Math.cos(a), 0.06, R0 * Math.sin(a));
      bar.rotation.y = -a;
      bar.userData.pick = index;
      group.add(bar);
    }
    // label
    const el = document.createElement('div');
    el.className = 'd3-label';
    el.innerHTML = `${d.avatar ? `<img class="d3-face" src="${escapeHtml(d.avatar)}" style="border-color:${d.color || '#4fc3f7'}" alt="">` : `<span class="d3-dot" style="background:${d.color || '#4fc3f7'}"></span>`}<span>${escapeHtml(d.name)}</span>${d.badge != null ? `<b class="d3-badge">${d.badge}</b>` : ''}`;
    const lab = new CSS2DObject(el); lab.position.set(R + 2.2, 0, 0); group.add(lab);
    // sector numerals
    if (this.opts.showSectorLabels !== false) {
      const numerals = new THREE.Group(); numerals.userData.numerals = true;
      for (const sec of SECTORS) {
        const a = ((-90 + (sec.id - 1) * 30) * Math.PI) / 180;
        const n = document.createElement('div'); n.className = 'd3-roman'; n.textContent = sec.roman;
        const o = new CSS2DObject(n); o.position.set((R + 1.1) * Math.cos(a), 0, (R + 1.1) * Math.sin(a)); numerals.add(o);
      }
      group.add(numerals);
    }
    this.root.add(group);
    return { data: d, group, label: el, targetY: 0 };
  }

  layout(immediate = false) {
    const n = this.layers.length;
    this.layers.forEach((L, i) => {
      let y = i * this.gap;
      if (this.selected != null) y += i > this.selected ? this.gap * 1.6 : i === this.selected ? this.gap * 0.8 : 0;
      L.targetY = y; if (immediate) L.group.position.y = y;
    });
    const top = (n - 1) * this.gap + (this.selected != null ? this.gap * 1.6 : 0);
    this.controls.target.set(0, top / 2, 0);
    if (immediate && !this._fitted && n) {
      // fit the whole stack into view the first time layers arrive
      const dir = this.camera.position.clone().normalize();
      this.camera.position.copy(dir.multiplyScalar(Math.max(33, 25 + top * 0.9))).add(new THREE.Vector3(0, top / 2, 0));
      this._fitted = true;
    }
  }

  setGap(g) { this.gap = g; this.layout(); }

  setSelected(index) {
    this.selected = index === this.selected ? null : index;
    this.layout(); this.applySelection();
    this.opts.onSelect?.(this.selected);
  }

  applySelection() {
    this.layers.forEach((L, i) => {
      const dim = this.selected != null && i !== this.selected;
      L.group.traverse(o => {
        if (!o.material) return;
        if (o.userData.baseOpacity == null) o.userData.baseOpacity = o.material.opacity;
        o.material.opacity = dim ? o.userData.baseOpacity * 0.15 : o.userData.baseOpacity;
      });
      L.label.classList.toggle('dim', dim);
      L.label.classList.toggle('sel', this.selected === i);
      L.group.children.filter(c => c.userData.numerals).forEach(g => { g.visible = this.selected == null ? i === 0 : i === this.selected; g.children.forEach(c => { c.element.style.display = g.visible ? '' : 'none'; }); });
    });
  }

  pick(e) {
    const rect = this.renderer.domElement.getBoundingClientRect();
    this.mouse.set(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    this.ray.setFromCamera(this.mouse, this.camera);
    const hits = this.ray.intersectObjects(this.root.children, true).filter(h => h.object.userData.pick != null);
    if (hits.length) this.setSelected(hits[0].object.userData.pick);
  }

  tick() {
    for (const L of this.layers) L.group.position.y += (L.targetY - L.group.position.y) * 0.15;
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
    this.labels.render(this.scene, this.camera);
  }

  dispose() {
    cancelAnimationFrame(this._raf); this.ro.disconnect();
    this.setLayers([]); this.renderer.dispose(); this.controls.dispose();
    this.renderer.domElement.remove(); this.labels.domElement.remove();
  }
}

function escapeHtml(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
