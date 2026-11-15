// =============================================================================
// Small DOM toolkit + shared dialogs (warning, upload, journal, questionnaire),
// login screen, header controls (language, user colour, clocks), toasts.
// =============================================================================
import { t, lang, LANGUAGES, setLanguage } from './i18n.js';
import { PARAMS, paramName, PARAM_BY_ID } from './params.js';
import { STATUS_COLOR } from './scoring.js';
import { formatTime, viewerZone, zoneLabel, nowInputValue, localInputToIso, toIana } from './time.js';

// ---- element helper ----------------------------------------------------------
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}
export const svgNS = 'http://www.w3.org/2000/svg';
export function s(tag, attrs = {}, ...children) {
  const el = document.createElementNS(svgNS, tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else el.setAttribute(k, v);
  }
  for (const c of children.flat(Infinity)) if (c != null && c !== false) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return el;
}
export function clear(el) { while (el.firstChild) el.firstChild.remove(); return el; }
export function esc(str) { return String(str ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

export function statusPill(status, label) {
  return h('span', { class: `pill pill-${status}` }, label ?? t(`status.${status}`));
}
export function statusDot(status) { return h('span', { class: `dot dot-${status}` }); }
export function initials(name = '') { return name.split(/\s+/).map(p => p[0]).join('').slice(0, 2).toUpperCase(); }
export function avatar(user, size = 32) {
  const style = { width: size + 'px', height: size + 'px', background: user?.color || '#4fc3f7', fontSize: size * 0.4 + 'px' };
  if (user?.avatar) return h('img', { class: 'avatar photo', src: user.avatar, alt: user.name || '', style: { ...style, borderColor: user.color || '#4fc3f7' } });
  return h('span', { class: 'avatar', style }, initials(user?.name));
}

/** Read an image file, centre-crop to a square and downscale (JPEG data URL). */
export function imageFileToAvatar(file, size = 192) {
  return new Promise((resolve, reject) => {
    if (!file || !file.type.startsWith('image/')) return reject(new Error('not an image'));
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const side = Math.min(img.naturalWidth, img.naturalHeight);
      const cv = document.createElement('canvas'); cv.width = cv.height = size;
      cv.getContext('2d').drawImage(img, (img.naturalWidth - side) / 2, (img.naturalHeight - side) / 2, side, side, 0, 0, size, size);
      URL.revokeObjectURL(url);
      resolve(cv.toDataURL('image/jpeg', 0.85));
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('cannot read image')); };
    img.src = url;
  });
}

/** Own profile picture: choose / replace / remove. Resolves to the new value (data URL or null) or undefined if cancelled. */
export async function profilePhotoDialog(api, user) {
  let value = user.avatar || null;
  const preview = h('div', { class: 'photo-preview' });
  const draw = () => { clear(preview).append(avatar({ ...user, avatar: value }, 128)); };
  draw();
  const file = h('input', { type: 'file', accept: 'image/*' });
  file.addEventListener('change', async () => {
    try { value = await imageFileToAvatar(file.files[0]); draw(); } catch (e) { toast(t('photo.invalid'), 'warn'); }
  });
  const body = h('div', { class: 'form' }, preview,
    h('label', { class: 'field' }, h('span', { class: 'field-label' }, t('photo.choose')), file, h('span', { class: 'field-hint' }, t('photo.hint'))),
    h('button', { class: 'btn ghost sm', type: 'button', onclick: () => { value = null; file.value = ''; draw(); } }, t('photo.remove')));
  const ok = await modal(t('photo.title'), body, { actions: [{ label: t('common.save'), onClick: async () => {
    await api.saveUserSettings(user.id, { avatar: value });
    toast(t('photo.saved'), 'ok');
    return true;
  } }] });
  return ok ? value : undefined;
}

// ---- toasts --------------------------------------------------------------------
export function toast(msg, kind = 'info', ms = 3500) {
  let host = document.querySelector('.toast-host');
  if (!host) { host = h('div', { class: 'toast-host' }); document.body.append(host); }
  const el = h('div', { class: `toast toast-${kind}` }, msg);
  host.append(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 400); }, ms);
}

// ---- modal ----------------------------------------------------------------------
export function modal(title, body, { actions = [], wide = false } = {}) {
  return new Promise(resolve => {
    const close = v => { back.remove(); resolve(v); };
    const footer = h('div', { class: 'modal-actions' },
      h('button', { class: 'btn ghost', onclick: () => close(null) }, t('common.cancel')),
      ...actions.map(a => h('button', { class: `btn ${a.kind || 'primary'}`, onclick: async () => { const v = await a.onClick?.(); if (v !== false) close(v ?? true); } }, a.label)));
    const box = h('div', { class: `modal ${wide ? 'wide' : ''}`, role: 'dialog', 'aria-modal': 'true' },
      h('div', { class: 'modal-head' }, h('h3', {}, title), h('button', { class: 'icon-btn', 'aria-label': t('common.close'), onclick: () => close(null) }, '✕')),
      h('div', { class: 'modal-body' }, body), footer);
    const back = h('div', { class: 'modal-back', onclick: e => { if (e.target === back) close(null); } }, box);
    document.body.append(back);
    box.querySelector('input,select,textarea,button')?.focus();
  });
}

function field(label, input, hint) {
  return h('label', { class: 'field' }, h('span', { class: 'field-label' }, label), input, hint ? h('span', { class: 'field-hint' }, hint) : null);
}
function paramSelect(selected, filter = () => true) {
  return h('select', {}, PARAMS.filter(filter).map(p => h('option', { value: p.id, selected: p.id === selected }, `${paramName(p, lang())} (${p.unit})`)));
}
function zoneSelect(selected = viewerZone()) {
  const zones = [...new Set([viewerZone(), 'UTC', 'LTC', 'Europe/Budapest', 'America/Houston', 'Europe/Moscow', 'Asia/Tokyo', 'Europe/Paris', 'Europe/Berlin', 'Europe/Rome', selected])];
  return h('select', {}, zones.map(z => h('option', { value: z, selected: z === selected }, zoneLabel(z))));
}

// ---- dialogs ----------------------------------------------------------------------
/** Send a warning to a user / team leader. */
export async function sendWarningDialog(api, { to, parameter, recipients }) {
  const toSel = recipients ? h('select', {}, recipients.map(r => h('option', { value: r.id, selected: r.id === to?.id }, `${r.name} — ${t('role.' + r.role)}`))) : null;
  const level = h('select', {}, ['info', 'warn', 'crit'].map(l => h('option', { value: l, selected: l === 'warn' }, t(`level.${l}`))));
  const par = paramSelect(parameter); par.prepend(h('option', { value: '', selected: !parameter }, '—'));
  const msg = h('textarea', { rows: 4, placeholder: t('warn.placeholder') });
  const body = h('div', { class: 'form' },
    toSel ? field(t('warn.to'), toSel) : h('p', {}, t('warn.to') + ': ', h('b', {}, to.name)),
    field(t('warn.level'), level), field(t('warn.parameter'), par), field(t('warn.message'), msg));
  return modal(t('warn.title'), body, { actions: [{ label: t('warn.send'), kind: 'danger', onClick: async () => {
    if (!msg.value.trim()) { msg.focus(); toast(t('warn.empty'), 'warn'); return false; }
    const toId = toSel ? toSel.value : to.id;
    await api.sendWarning({ toId, level: level.value, parameter: par.value || null, message: msg.value.trim() });
    toast(t('warn.sent'), 'ok');
    return true;
  } }] });
}

/** Upload: JSON file(s) (server format) or a quick manual entry. Both may be marked private. */
export async function uploadDialog(api, user) {
  const fileIn = h('input', { type: 'file', accept: '.json,application/json', multiple: true });
  const par = paramSelect('heartRate', p => !p.env || true);
  const val = h('input', { type: 'number', step: 'any', required: true });
  const time = h('input', { type: 'datetime-local', value: nowInputValue() });
  const zone = zoneSelect();
  const priv = h('input', { type: 'checkbox' });
  const unit = h('span', { class: 'muted' }, PARAM_BY_ID[par.value].unit);
  par.addEventListener('change', () => { unit.textContent = PARAM_BY_ID[par.value].unit; });
  const tabs = h('div', { class: 'seg' });
  const paneFile = h('div', { class: 'form' }, field(t('upload.file'), fileIn, t('upload.fileHint')));
  const paneManual = h('div', { class: 'form hidden' }, field(t('warn.parameter'), par), field(t('upload.value'), h('div', { class: 'row' }, val, unit)), h('div', { class: 'row2' }, field(t('common.time'), time), field(t('common.timezone'), zone)));
  let mode = 'file';
  const mk = (m, k) => h('button', { class: `seg-btn ${m === mode ? 'on' : ''}`, onclick: () => { mode = m; tabs.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('on', b.dataset.m === m)); paneFile.classList.toggle('hidden', m !== 'file'); paneManual.classList.toggle('hidden', m !== 'manual'); }, 'data-m': m }, t(k));
  tabs.append(mk('file', 'upload.tabFile'), mk('manual', 'upload.tabManual'));
  const body = h('div', {}, tabs, paneFile, paneManual, h('label', { class: 'check' }, priv, h('span', {}, t('upload.private')), h('span', { class: 'field-hint' }, t('upload.privateHint'))));
  return modal(t('upload.title'), body, { actions: [{ label: t('upload.submit'), onClick: async () => {
    try {
      if (mode === 'file') {
        if (!fileIn.files.length) { toast(t('upload.noFile'), 'warn'); return false; }
        let n = 0;
        for (const f of fileIn.files) {
          const json = JSON.parse(await f.text());
          const list = Array.isArray(json) ? json : [json];
          for (const m of list) { await api.upload({ ...m, userId: m.userId || user.id, private: priv.checked || !!m.private }); n++; }
        }
        toast(t('upload.done', { n }), 'ok');
      } else {
        if (val.value === '') { val.focus(); return false; }
        await api.upload({ schemaVersion: '1.0', userId: user.id, parameter: par.value, unit: PARAM_BY_ID[par.value].unit, type: 'single', private: priv.checked,
          source: { device: 'manual', timezone: zone.value }, samples: [{ t: localInputToIso(time.value, toIana(zone.value)), v: Number(val.value) }] });
        toast(t('upload.done', { n: 1 }), 'ok');
      }
      return true;
    } catch (e) { toast(t('upload.error') + ': ' + e.message, 'crit', 6000); return false; }
  } }] });
}

/** Journal entry: name, time (+zone), metadata (key/value), text, private flag. */
export async function journalDialog(api, user) {
  const name = h('input', { type: 'text', placeholder: t('journal.namePh') });
  const time = h('input', { type: 'datetime-local', value: nowInputValue() });
  const zone = zoneSelect();
  const text = h('textarea', { rows: 4 });
  const priv = h('input', { type: 'checkbox' });
  const metaRows = h('div', { class: 'meta-rows' });
  const addMeta = (k = '', v = '') => metaRows.append(h('div', { class: 'row' }, h('input', { type: 'text', placeholder: t('journal.metaKey'), value: k }), h('input', { type: 'text', placeholder: t('journal.metaValue'), value: v }), h('button', { class: 'icon-btn', onclick: e => e.currentTarget.parentElement.remove() }, '✕')));
  addMeta('category', ''); addMeta('location', '');
  const body = h('div', { class: 'form' }, field(t('journal.name') + ' *', name), h('div', { class: 'row2' }, field(t('common.time') + ' *', time), field(t('common.timezone'), zone)),
    field(t('journal.meta'), h('div', {}, metaRows, h('button', { class: 'btn ghost sm', onclick: () => addMeta() }, '+ ' + t('journal.addMeta')))),
    field(t('journal.text'), text), h('label', { class: 'check' }, priv, h('span', {}, t('upload.private'))));
  return modal(t('journal.add'), body, { actions: [{ label: t('common.save'), onClick: async () => {
    if (!name.value.trim()) { name.focus(); toast(t('journal.required'), 'warn'); return false; }
    const meta = {};
    metaRows.querySelectorAll('.row').forEach(r => { const [k, v] = r.querySelectorAll('input'); if (k.value.trim()) meta[k.value.trim()] = v.value; });
    await api.journalAdd({ userId: user.id, name: name.value.trim(), time: localInputToIso(time.value, toIana(zone.value)), timezone: zone.value, meta, text: text.value, private: priv.checked });
    toast(t('journal.saved'), 'ok');
    return true;
  } }] });
}

/** Questionnaire (sleep diary, mood screening). Derives a parameter value. */
export async function questionnaireDialog(api, user, q) {
  const inputs = {};
  const rows = q.items.map(it => {
    let inp;
    if (it.type === 'scale') {
      inp = h('div', { class: 'scale' }, Array.from({ length: it.max - it.min + 1 }, (_, i) => it.min + i).map(v => h('label', { class: 'scale-opt' }, h('input', { type: 'radio', name: it.id, value: v }), h('span', {}, v))));
    } else inp = h('input', { type: it.type === 'time' ? 'time' : 'number', min: 0 });
    inputs[it.id] = { it, inp };
    return field(t(it.key), inp);
  });
  const priv = h('input', { type: 'checkbox', checked: q.id === 'mood' });
  const note = q.id === 'mood' ? h('p', { class: 'field-hint' }, t('q.mood.note')) : q.id === 'confinement' ? h('p', { class: 'field-hint' }, t('q.confinement.note')) : null;
  return modal(t(q.titleKey), h('div', { class: 'form' }, note, rows, h('label', { class: 'check' }, priv, h('span', {}, t('upload.private')))), { actions: [{ label: t('common.submit'), onClick: async () => {
    const answers = {};
    for (const [id, { it, inp }] of Object.entries(inputs)) {
      answers[id] = it.type === 'scale' ? Number(inp.querySelector('input:checked')?.value ?? NaN) : inp.value;
      if (answers[id] === '' || Number.isNaN(answers[id])) { toast(t('q.incomplete'), 'warn'); return false; }
    }
    let derived = null;
    if (q.id === 'sleep') {
      const [bh, bm] = answers.bed.split(':').map(Number), [wh, wm] = answers.wake.split(':').map(Number);
      let mins = (wh * 60 + wm) - (bh * 60 + bm); if (mins < 0) mins += 1440;
      derived = { parameter: 'sleepTime', value: +(mins / 60).toFixed(2) };
    } else if (q.parameter) derived = { parameter: q.parameter, value: Object.values(answers).reduce((a, b) => a + Number(b || 0), 0) };
    await api.submitQuestionnaire({ userId: user.id, questionnaireId: q.id, time: new Date().toISOString(), timezone: viewerZone(), answers, derived, private: priv.checked });
    toast(t('q.saved'), 'ok');
    return true;
  } }] });
}

// ---- header controls ------------------------------------------------------------------
export function languageSelect() {
  const sel = h('select', { class: 'lang-select', 'aria-label': 'Language' }, LANGUAGES.map(l => h('option', { value: l.code, selected: l.code === lang() }, l.label)));
  sel.addEventListener('change', () => setLanguage(sel.value));
  return sel;
}

export function colorPicker(user, onChange) {
  const inp = h('input', { type: 'color', value: user.color || '#4fc3f7', title: t('user.color'), class: 'color-pick' });
  inp.addEventListener('change', () => onChange(inp.value));
  return inp;
}

/** Clocks: viewer local, UTC and (optionally) the data source's zone. */
export function clocks(sourceZone) {
  const el = h('div', { class: 'clocks' });
  const tick = () => {
    const now = new Date();
    el.innerHTML = '';
    el.append(h('span', { title: viewerZone() }, h('small', {}, t('time.local')), formatTime(now, { withDate: false, seconds: true, lang: lang() })));
    el.append(h('span', {}, h('small', {}, 'UTC'), formatTime(now, { zone: 'UTC', withDate: false, seconds: true, lang: lang() })));
    const sz = typeof sourceZone === 'function' ? sourceZone() : sourceZone;
    if (sz && toIana(sz) !== 'UTC' && toIana(sz) !== toIana(viewerZone())) el.append(h('span', {}, h('small', {}, zoneLabel(sz)), formatTime(now, { zone: sz, withDate: false, seconds: true, lang: lang() })));
    else if (sz === 'LTC') el.append(h('span', { title: 'Coordinated Lunar Time (= UTC in v1)' }, h('small', {}, 'LTC'), formatTime(now, { zone: 'UTC', withDate: false, seconds: true, lang: lang() })));
  };
  tick();
  let seen = false;
  const id = setInterval(() => { if (el.isConnected) seen = true; else if (seen) { clearInterval(id); return; } tick(); }, 1000);
  return el;
}

// ---- login screen -------------------------------------------------------------------------
export function loginScreen(root, api, { appTitleKey, subtitleKey, onLogin }) {
  clear(root);
  const user = h('input', { type: 'text', autocomplete: 'username', placeholder: t('login.username') });
  const pass = h('input', { type: 'password', autocomplete: 'current-password', placeholder: t('login.password') });
  const err = h('div', { class: 'login-err' });
  const go = async (u, p) => {
    err.textContent = '';
    try { onLogin(await api.login(u, p)); } catch (e) { err.textContent = t('login.failed') + (e.message ? ` (${e.message})` : ''); }
  };
  const form = h('form', { class: 'login-form', onsubmit: e => { e.preventDefault(); go(user.value.trim(), pass.value); } },
    user, pass, h('button', { class: 'btn primary', type: 'submit' }, t('login.submit')), err);
  const demo = h('div', { class: 'demo-accounts' });
  Promise.resolve(api.demoAccounts?.()).then(list => {
    if (!list?.length) return;
    demo.append(h('div', { class: 'muted small' }, t('login.demo')));
    demo.append(h('div', { class: 'demo-list' }, list.map(u => h('button', { class: 'demo-btn', type: 'button', onclick: () => go(u.id, '') }, avatar(u, 26), h('span', {}, u.name, h('small', {}, t('role.' + u.role)))))));
  });
  root.append(h('div', { class: 'login-wrap' },
    h('div', { class: 'login-card' },
      h('div', { class: 'brand big' }, h('span', { class: 'brand-mark' }), h('div', {}, h('div', { class: 'brand-name' }, t(appTitleKey)), h('div', { class: 'brand-sub' }, t(subtitleKey)))),
      h('div', { class: 'login-lang' }, languageSelect()),
      form, demo)));
  user.focus();
}

export function modeBadge(api) {
  const m = api.mode;
  return h('span', { class: `mode-badge mode-${m}`, title: t('mode.' + m) }, m === 'live' ? 'LIVE' : 'DEMO');
}

export { STATUS_COLOR };
