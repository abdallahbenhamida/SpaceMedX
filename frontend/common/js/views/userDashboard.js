// =============================================================================
// User dashboard — one person's data as a grid of tiles.
// Used by all three projects with different modes:
//   self       Single User: own data, "+" to add tiles, upload, journal,
//              questionnaires, warning inbox, privacy/consent management
//   leader     Team Leader looking at a member: scores only, send warning,
//              request consent for private data
//   operator   Ground Control (non-medical): scores only, send warning
//   physician  Ground Control physician: raw values, ECG, ultrasound/DICOM,
//              PDFs, evaluation form
// =============================================================================
import { h, s, clear, modal, toast, statusPill, statusDot, avatar, sendWarningDialog, uploadDialog, journalDialog, questionnaireDialog } from '../ui.js';
import { t, lang, onLanguageChange } from '../i18n.js';
import { PARAMS, PARAM_BY_ID, SECTORS, paramName, BODY_POINTS } from '../params.js';
import { evaluate, summarize, readinessStatus, rankFor, STATUS_COLOR } from '../scoring.js';
import { formatDual, formatTime, relative, queryWindow, zoneLabel } from '../time.js';
import { renderDisk } from '../components/diskChart.js';
import { renderSuit } from '../components/suitView.js';
import { renderMap } from '../components/mapView.js';
import { trendChart, gauge, ecgChart } from '../components/charts.js';

const MODES = { self: 'self', leader: 'leader', operator: 'operator', physician: 'physician' };

// ---- tile catalogue ----------------------------------------------------------------
const TILES = {
  readiness: { titleKey: 'tile.readiness', size: 's', modes: ['self', 'leader', 'operator', 'physician'] },
  suit: { titleKey: 'tile.suit', size: 't', modes: ['self', 'leader', 'operator', 'physician'] },
  disk: { titleKey: 'tile.disk', size: 'l', modes: ['self', 'leader', 'operator', 'physician'] },
  env: { titleKey: 'tile.env', size: 'm', modes: ['self', 'leader', 'operator', 'physician'] },
  paramList: { titleKey: 'tile.paramList', size: 'm', modes: ['self', 'leader', 'operator', 'physician'] },
  trend: { titleKey: 'tile.trend', size: 'm', modes: ['self', 'leader', 'operator', 'physician'], opts: { param: 'heartRate' } },
  map: { titleKey: 'tile.map', size: 'm', modes: ['self', 'leader', 'operator', 'physician'] },
  journal: { titleKey: 'tile.journal', size: 's', modes: ['self', 'leader', 'operator', 'physician'] },
  questionnaires: { titleKey: 'tile.questionnaires', size: 's', modes: ['self'] },
  inbox: { titleKey: 'tile.inbox', size: 's', modes: ['self'] },
  privacy: { titleKey: 'tile.privacy', size: 's', modes: ['self'] },
  media: { titleKey: 'tile.media', size: 's', modes: ['self', 'leader', 'operator', 'physician'] },
  raw: { titleKey: 'tile.raw', size: 'l', modes: ['physician'] },
  ecg: { titleKey: 'tile.ecg', size: 'm', modes: ['physician'] },
  evaluation: { titleKey: 'tile.evaluation', size: 'm', modes: ['physician'] },
};

const DEFAULT_LAYOUT = {
  self: ['suit', 'disk', 'readiness', 'inbox', 'trend', 'env', 'journal', 'questionnaires', 'privacy', 'media'],
  leader: ['suit', 'disk', 'readiness', 'media', 'paramList', 'trend', 'journal', 'map'],
  operator: ['suit', 'disk', 'readiness', 'media', 'paramList', 'env', 'trend', 'map'],
  physician: ['suit', 'disk', 'readiness', 'evaluation', 'raw', 'ecg', 'trend', 'media', 'journal', 'env'],
};

let tileSeq = 0;
const newTile = (type, opts) => ({ key: `${type}-${Date.now().toString(36)}-${tileSeq++}`, type, opts: { ...(TILES[type].opts || {}), ...(opts || {}) } });

/**
 * @param {HTMLElement} host
 * @param {object} ctx { api, config, viewer, subjectId, mode, onBack, onUserChange, recipients }
 */
export function renderUserDashboard(host, ctx) {
  const { api, config, viewer, subjectId, mode } = ctx;
  const showValues = mode === MODES.physician || config.privacy?.showRawValuesToNonPhysicians;
  const layoutKey = `shm_layout_${mode}_${viewer.id}`;
  let layout = loadLayout();
  const state = { user: null, latest: null, inbox: [], consents: [], journal: [], attachments: [], evaluations: [], questionnaires: [], sentConsents: [] };
  const tileEls = new Map();
  let timers = [], destroyed = false;

  const root = h('div', { class: 'dash' });
  const head = h('div', { class: 'dash-head' });
  const grid = h('div', { class: 'tiles' });
  root.append(head, grid);
  clear(host).append(root);

  function loadLayout() {
    try { const l = JSON.parse(localStorage.getItem(layoutKey)); if (Array.isArray(l) && l.length) return l.filter(x => TILES[x.type]?.modes.includes(mode)); } catch { /* ignore */ }
    return DEFAULT_LAYOUT[mode].map(type => newTile(type));
  }
  function saveLayout() { localStorage.setItem(layoutKey, JSON.stringify(layout)); }

  // ---- data -----------------------------------------------------------------------------
  async function loadAll() {
    const tasks = [
      api.getUser(subjectId).then(async u => { state.user = u; if (!ctx.teamName && u?.teamId) { const ts = await api.listTeams(); state.teamName = ts.find(x => x.id === u.teamId)?.name; } }),
      api.latest(subjectId).then(l => { state.latest = l; }),
      api.journalList(subjectId).then(j => { state.journal = j || []; }).catch(() => { state.journal = []; }),
      Promise.resolve(api.attachments?.(subjectId)).then(a => { state.attachments = a || []; }).catch(() => { state.attachments = []; }),
    ];
    if (mode === MODES.self) {
      tasks.push(api.inbox(subjectId).then(w => { state.inbox = w || []; }));
      tasks.push(api.listConsents(subjectId).then(c => { state.consents = c || []; }));
      tasks.push(api.questionnaires().then(q => { state.questionnaires = q || []; }));
    }
    if (mode === MODES.leader) tasks.push(api.listConsents(viewer.id).then(c => { state.sentConsents = (c || []).filter(x => x.ownerId === subjectId && x.requesterId === viewer.id); }));
    if (mode === MODES.physician) tasks.push(api.listEvaluations(subjectId).then(e => { state.evaluations = e || []; }).catch(() => { state.evaluations = []; }));
    await Promise.all(tasks);
  }

  async function refreshLatest() {
    try { state.latest = await api.latest(subjectId); renderHead(); rerender(['readiness', 'disk', 'suit', 'env', 'paramList', 'raw', 'map']); } catch (e) { console.warn(e); }
  }
  async function refreshInbox() {
    try {
      const before = new Set(state.inbox.map(w => w.id));
      state.inbox = await api.inbox(subjectId);
      const fresh = state.inbox.filter(w => !before.has(w.id) && !w.ack);
      fresh.forEach(w => toast(`⚠ ${w.fromName}: ${w.message}`, w.level === 'crit' ? 'crit' : 'warn', 7000));
      state.consents = await api.listConsents(subjectId);
      renderHead(); rerender(['inbox', 'privacy']);
    } catch (e) { console.warn(e); }
  }

  // ---- header -------------------------------------------------------------------------------
  function renderHead() {
    clear(head);
    const u = state.user; if (!u || !state.latest) return;
    const sum = summarize(state.latest.values);
    const locked = Object.values(state.latest.values).filter(v => v.locked).length;
    const tz = state.latest.timezone;
    const left = h('div', { class: 'who' },
      ctx.onBack ? h('button', { class: 'btn ghost sm', onclick: ctx.onBack }, '← ' + t('common.back')) : null,
      avatar(u, 44),
      h('div', {}, h('div', { class: 'who-name' }, u.name), h('div', { class: 'who-sub' }, t('role.' + u.role), ' · ', ctx.teamName || state.teamName || '', ' · ', t('map.' + state.latest.frame), ' · ', h('span', { title: tz }, `${zoneLabel(tz)} ${formatTime(new Date(), { zone: tz, withDate: false, lang: lang() })}`))),
      statusPill(readinessStatus(sum.readiness), `${t('tile.readiness')}: ${sum.readiness ?? '–'}`));
    const actions = h('div', { class: 'dash-actions' });
    if (mode === MODES.self) {
      const unread = state.inbox.filter(w => !w.ack).length;
      const pending = state.consents.filter(c => c.ownerId === subjectId && c.status === 'pending').length;
      if (unread) actions.append(h('span', { class: 'badge crit', title: t('tile.inbox') }, `⚠ ${unread}`));
      if (pending) actions.append(h('span', { class: 'badge warn', title: t('tile.privacy') }, `🔑 ${pending}`));
      actions.append(
        h('button', { class: 'btn', onclick: async () => { if (await uploadDialog(api, u)) refreshLatest(); } }, '⇪ ' + t('upload.title')),
        h('button', { class: 'btn', onclick: async () => { if (await journalDialog(api, u)) { state.journal = await api.journalList(subjectId); rerender(['journal']); } } }, '✎ ' + t('journal.add')));
    } else {
      if (locked && mode === MODES.leader) {
        const pend = state.sentConsents.find(c => c.status === 'pending');
        actions.append(h('span', { class: 'muted small' }, `🔒 ${t('privacy.lockedCount', { n: locked })}`));
        actions.append(pend ? h('span', { class: 'badge warn' }, t('privacy.requested')) : h('button', { class: 'btn', onclick: requestAccess }, '🔑 ' + t('privacy.request')));
      }
      actions.append(h('button', { class: 'btn danger', onclick: () => sendWarningDialog(api, { to: u, recipients: ctx.recipients?.(u) }) }, '⚠ ' + t('warn.title')));
    }
    actions.append(h('button', { class: 'btn primary add-tile', title: t('tiles.add'), onclick: addTileDialog }, '+'));
    head.append(left, actions);
  }

  async function requestAccess() {
    const reason = h('textarea', { rows: 3, placeholder: t('privacy.reasonPh') });
    const ok = await modal(t('privacy.request'), h('div', { class: 'form' }, h('p', {}, t('privacy.requestInfo', { name: state.user.name })), reason), { actions: [{ label: t('privacy.send'), onClick: async () => {
      await api.requestConsent({ ownerId: subjectId, scope: 'all-private', reason: reason.value.trim() });
      return true;
    } }] });
    if (ok) { toast(t('privacy.requested'), 'ok'); state.sentConsents = (await api.listConsents(viewer.id)).filter(x => x.ownerId === subjectId); renderHead(); }
  }

  async function addTileDialog() {
    const types = Object.entries(TILES).filter(([, d]) => d.modes.includes(mode));
    const list = h('div', { class: 'tile-picker' }, types.map(([type, d]) => h('button', { class: 'tile-pick', onclick: () => {
      layout.push(newTile(type)); saveLayout(); renderGrid(); document.querySelector('.modal-back')?.remove();
      setTimeout(() => grid.lastElementChild?.scrollIntoView({ behavior: 'smooth', block: 'center' }), 50);
    } }, h('span', { class: `tp-icon tp-${type}` }), t(d.titleKey))));
    await modal(t('tiles.add'), h('div', {}, h('p', { class: 'muted' }, t('tiles.addInfo')), list), { wide: true });
  }

  // ---- grid -----------------------------------------------------------------------------------
  function renderGrid() {
    clear(grid); tileEls.clear();
    layout.forEach((tile, idx) => {
      const def = TILES[tile.type];
      const body = h('div', { class: 'tile-body' });
      const extra = h('div', { class: 'tile-extra' });
      const el = h('section', { class: `tile size-${def.size} tile-${tile.type}`, draggable: 'true', 'data-key': tile.key },
        h('header', { class: 'tile-head' }, h('h4', {}, t(def.titleKey)), extra,
          h('button', { class: 'icon-btn', title: t('tiles.remove'), onclick: () => { layout = layout.filter(x => x.key !== tile.key); saveLayout(); renderGrid(); } }, '✕')),
        body);
      el.addEventListener('dragstart', e => { e.dataTransfer.setData('text/plain', tile.key); el.classList.add('dragging'); });
      el.addEventListener('dragend', () => el.classList.remove('dragging'));
      el.addEventListener('dragover', e => { e.preventDefault(); el.classList.add('drop'); });
      el.addEventListener('dragleave', () => el.classList.remove('drop'));
      el.addEventListener('drop', e => {
        e.preventDefault(); el.classList.remove('drop');
        const from = layout.findIndex(x => x.key === e.dataTransfer.getData('text/plain'));
        if (from < 0 || from === idx) return;
        const [m] = layout.splice(from, 1); layout.splice(idx, 0, m); saveLayout(); renderGrid();
      });
      grid.append(el);
      tileEls.set(tile.key, { tile, body, extra });
      renderTile(tile.key);
    });
    grid.append(h('button', { class: 'tile tile-add size-s', onclick: addTileDialog }, h('span', { class: 'plus' }, '+'), h('span', {}, t('tiles.add'))));
  }

  function rerender(types) { for (const [key, { tile }] of tileEls) if (types.includes(tile.type)) renderTile(key); }

  function renderTile(key) {
    const entry = tileEls.get(key); if (!entry || !state.latest) return;
    const { tile, body, extra } = entry;
    clear(body); clear(extra);
    try { RENDER[tile.type]?.(body, tile, extra); } catch (e) { console.error(e); body.append(h('div', { class: 'muted' }, 'Error: ' + e.message)); }
  }

  // ---- tile renderers ----------------------------------------------------------------------------------
  const latestValues = () => state.latest?.values || {};

  async function openParam(paramId) {
    const p = PARAM_BY_ID[paramId]; const m = latestValues()[paramId];
    const body = h('div', {});
    const ev = m?.v != null ? evaluate(p, m.v) : null;
    body.append(h('div', { class: 'param-head' },
      ev ? statusPill(ev.status) : statusPill('none', m?.locked ? '🔒 ' + t('privacy.locked') : t('common.noData')),
      ev ? h('span', { class: 'big-score' }, `${ev.score}`, h('small', {}, '/100')) : null,
      showValues && ev ? h('span', { class: 'raw' }, `${m.v} ${p.unit}`) : null,
      showValues ? h('span', { class: 'muted small' }, `ok ${p.ok[0]}–${p.ok[1]} · warn ${p.warn[0]}–${p.warn[1]} ${p.unit}`) : null,
      h('span', { class: 'muted small' }, t('mode.' + p.mode), ' · ', t('source.' + p.source))));
    const chartHost = h('div', { class: 'chart-host' }); body.append(chartHost);
    modal(paramName(p, lang()), body, { wide: true, actions: mode !== MODES.self ? [{ label: '⚠ ' + t('warn.title'), kind: 'danger', onClick: () => { sendWarningDialog(api, { to: state.user, parameter: paramId, recipients: ctx.recipients?.(state.user) }); return true; } }] : [] });
    if (m?.locked) { chartHost.append(h('p', { class: 'muted' }, '🔒 ' + t('privacy.locked'))); return; }
    try {
      const ms = await api.measurements(subjectId, paramId, queryWindow(config.history.defaultHours));
      trendChart(chartHost, { param: p, samples: ms.flatMap(x => x.samples || []), showValues, sourceZone: ms[0]?.source?.timezone });
      if (ms[0]?.source) chartHost.append(h('div', { class: 'muted small' }, `${t('common.source')}: ${ms[0].source.device || '–'} · ${zoneLabel(ms[0].source.timezone)}`));
    } catch (e) { chartHost.append(h('p', { class: 'muted' }, e.message === 'consent-required' ? '🔒 ' + t('privacy.locked') : e.message)); }
  }

  const RENDER = {
    readiness(body) {
      const sum = summarize(latestValues());
      const st = readinessStatus(sum.readiness);
      const streak = 1 + (hashStr(subjectId) % 9);
      const rank = rankFor(sum.readiness, streak);
      const g = h('div', { class: 'gauge-host' }); gauge(g, { value: sum.readiness, status: st, label: t('ready.short') });
      const msg = st === 'ok' ? t('ready.ok') : st === 'warn' ? t('ready.warn') : st === 'crit' ? t('ready.crit') : t('common.noData');
      body.append(h('div', { class: 'readiness' }, g,
        h('div', { class: 'ready-info' },
          h('div', { class: `ready-msg st-${st}` }, msg),
          h('div', { class: 'counts' }, h('span', { class: 'c-ok' }, `● ${sum.counts.ok}`), h('span', { class: 'c-warn' }, `▲ ${sum.counts.warn}`), h('span', { class: 'c-crit' }, `■ ${sum.counts.crit}`)),
          h('div', { class: 'rank' }, h('b', {}, t(rank.rankKey)), ` · ${t('ready.level')} ${rank.level}`),
          h('div', { class: 'xp' }, h('div', { class: 'xp-bar' }, h('span', { style: { width: `${Math.min(100, ((rank.xp % 400) / 400) * 100)}%` } })), h('small', {}, `${rank.xp} XP · 🔥 ${t('ready.streak', { n: streak })}`)))));
    },
    disk(body) {
      const sum = summarize(latestValues());
      const host = h('div', { class: 'disk-host' }); body.append(host);
      renderDisk(host, { latest: latestValues(), showValues, onSelect: openParam, center: { value: sum.readiness ?? '–', status: readinessStatus(sum.readiness), label: t('ready.short') } });
      body.append(legend());
    },
    suit(body) {
      const host = h('div', { class: 'suit-host' }); body.append(host);
      renderSuit(host, { latest: latestValues(), color: state.user?.color, showValues, onSelect: (key, list) => {
        const items = h('div', { class: 'plist' }, list.map(p => paramRow(p)));
        modal(t(BODY_POINTS[key].key), items, { wide: false });
      } });
    },
    env(body) {
      const grid2 = h('div', { class: 'env-grid' });
      for (const p of PARAMS.filter(x => x.env)) {
        const m = latestValues()[p.id]; const ev = m?.v != null ? evaluate(p, m.v) : null;
        grid2.append(h('button', { class: `env-cell st-${ev?.status || 'none'}`, onclick: () => openParam(p.id) },
          h('span', { class: 'env-name' }, paramName(p, lang())),
          h('span', { class: 'env-val' }, m?.v != null ? `${m.v}` : '–', h('small', {}, ' ' + p.unit)),
          h('span', { class: 'meter' }, h('i', { style: { width: `${(ev?.pos ?? 0) * 100}%`, background: STATUS_COLOR[ev?.status || 'none'] } }))));
      }
      body.append(grid2);
    },
    paramList(body) {
      const wrap = h('div', { class: 'plist scroll' });
      for (const sec of SECTORS) {
        const list = PARAMS.filter(p => p.sector === sec.id && !p.env); if (!list.length) continue;
        wrap.append(h('div', { class: 'plist-sec' }, `${sec.roman} · ${t(sec.key)}`));
        list.forEach(p => wrap.append(paramRow(p)));
      }
      body.append(wrap);
    },
    raw(body) {
      const tbl = h('table', { class: 'raw-table' }, h('thead', {}, h('tr', {}, ['', t('raw.param'), t('raw.value'), t('raw.unit'), t('raw.ok'), t('raw.warn'), t('raw.time'), t('raw.type')].map(x => h('th', {}, x)))));
      const tb = h('tbody'); tbl.append(tb);
      const tz = state.latest.timezone;
      for (const p of PARAMS) {
        const m = latestValues()[p.id]; const ev = m?.v != null ? evaluate(p, m.v) : null;
        tb.append(h('tr', { class: `st-${ev?.status || 'none'}`, onclick: () => openParam(p.id) },
          h('td', {}, statusDot(ev?.status || 'none')), h('td', {}, paramName(p, lang()), p.clinical ? h('sup', { class: 'clin' }, 'Rx') : null, m?.private ? ' 🔒' : ''),
          h('td', { class: 'num' }, m?.v ?? '–'), h('td', {}, p.unit), h('td', {}, `${p.ok[0]}–${p.ok[1]}`), h('td', {}, `${p.warn[0]}–${p.warn[1]}`),
          h('td', { class: 'small' }, m?.t ? formatDual(m.t, tz, lang()) : '–'), h('td', { class: 'small' }, t('mode.' + p.mode))));
      }
      body.append(h('div', { class: 'scroll' }, tbl));
    },
    trend(body, tile, extra) {
      const sel = h('select', { class: 'sm' }, PARAMS.map(p => h('option', { value: p.id, selected: p.id === tile.opts.param }, paramName(p, lang()))));
      sel.addEventListener('change', () => { tile.opts.param = sel.value; saveLayout(); renderTile(tile.key); });
      extra.append(sel);
      const host = h('div', { class: 'chart-host' }); body.append(host);
      const p = PARAM_BY_ID[tile.opts.param];
      if (latestValues()[p.id]?.locked) { host.append(h('p', { class: 'muted' }, '🔒 ' + t('privacy.locked'))); return; }
      api.measurements(subjectId, p.id, queryWindow(config.history.defaultHours))
        .then(ms => trendChart(host, { param: p, samples: ms.flatMap(x => x.samples || []), showValues }))
        .catch(e => host.append(h('p', { class: 'muted' }, e.message)));
    },
    map(body) {
      const l = state.latest; const sum = summarize(l.values);
      const host = h('div', { class: 'map-host' }); body.append(host);
      renderMap(host, { frame: l.frame, points: [{ ...l.location, label: state.user.name, sub: l.location.module || `${l.location.lat}, ${l.location.lon}`, short: state.user.name.split(' ')[0], avatar: state.user.avatar, color: state.user.color, status: sum.overall, time: formatDual(new Date(), l.timezone, lang()) }] });
    },
    journal(body, tile, extra) {
      if (mode === MODES.self) extra.append(h('button', { class: 'btn sm', onclick: async () => { if (await journalDialog(api, state.user)) { state.journal = await api.journalList(subjectId); renderTile(tile.key); } } }, '+'));
      const list = h('div', { class: 'list scroll' });
      if (!state.journal.length) list.append(h('p', { class: 'muted' }, t('journal.empty')));
      state.journal.forEach(j => list.append(h('div', { class: 'list-item' },
        h('div', { class: 'li-top' }, h('b', {}, j.name), j.private ? h('span', { class: 'lock' }, '🔒') : null, h('span', { class: 'muted small' }, formatDual(j.time, j.timezone, lang()))),
        j.locked ? h('div', { class: 'muted small' }, t('privacy.locked')) : [
          Object.keys(j.meta || {}).length ? h('div', { class: 'chips' }, Object.entries(j.meta).filter(([, v]) => v !== '').map(([k, v]) => h('span', { class: 'chip' }, `${k}: ${v}`))) : null,
          j.text ? h('div', { class: 'li-text' }, j.text) : null])));
      body.append(list);
    },
    questionnaires(body) {
      const list = h('div', { class: 'list' });
      state.questionnaires.forEach(q => list.append(h('div', { class: 'list-item row-between' },
        h('div', {}, h('b', {}, t(q.titleKey)), h('div', { class: 'muted small' }, t('q.freq.' + q.frequency))),
        h('button', { class: 'btn sm primary', onclick: async () => { if (await questionnaireDialog(api, state.user, q)) refreshLatest(); } }, t('q.fill')))));
      body.append(list);
    },
    inbox(body) {
      const list = h('div', { class: 'list scroll' });
      if (!state.inbox.length) list.append(h('p', { class: 'muted' }, t('inbox.empty')));
      state.inbox.forEach(w => list.append(h('div', { class: `list-item warn-item lvl-${w.level} ${w.ack ? 'acked' : ''}` },
        h('div', { class: 'li-top' }, h('span', { class: `pill pill-${w.level === 'info' ? 'none' : w.level}` }, t('level.' + w.level)), h('b', {}, w.fromName || '?'), h('span', { class: 'muted small' }, relative(w.time, lang()))),
        w.parameter ? h('div', { class: 'small' }, paramName(w.parameter, lang())) : null,
        h('div', { class: 'li-text' }, w.message),
        w.ack ? h('div', { class: 'muted small' }, '✓ ' + t('inbox.acked')) : h('button', { class: 'btn sm', onclick: async () => { await api.ackWarning(w.id); w.ack = true; renderHead(); rerender(['inbox']); } }, t('inbox.ack')))));
      body.append(list);
    },
    privacy(body) {
      const mine = state.consents.filter(c => c.ownerId === subjectId);
      const list = h('div', { class: 'list scroll' });
      const privParams = Object.entries(latestValues()).filter(([, v]) => v.private).map(([k]) => paramName(k, lang()));
      list.append(h('div', { class: 'small muted' }, t('privacy.privateParams'), ': ', privParams.join(', ') || '–'));
      if (!mine.length) list.append(h('p', { class: 'muted' }, t('privacy.none')));
      mine.sort((a, b) => b.time.localeCompare(a.time)).forEach(c => list.append(h('div', { class: 'list-item' },
        h('div', { class: 'li-top' }, h('b', {}, c.requesterName), h('span', { class: `pill pill-${c.status === 'granted' ? 'ok' : c.status === 'pending' ? 'warn' : 'none'}` }, t('consent.' + c.status))),
        c.reason ? h('div', { class: 'li-text' }, c.reason) : null,
        h('div', { class: 'row' },
          c.status !== 'granted' ? h('button', { class: 'btn sm primary', onclick: async () => { await api.respondConsent(c.id, true); c.status = 'granted'; toast(t('consent.grantedToast'), 'ok'); rerender(['privacy']); renderHead(); } }, t('consent.grant')) : null,
          c.status === 'pending' ? h('button', { class: 'btn sm ghost', onclick: async () => { await api.respondConsent(c.id, false); c.status = 'denied'; rerender(['privacy']); renderHead(); } }, t('consent.deny')) : null,
          c.status === 'granted' ? h('button', { class: 'btn sm ghost', onclick: async () => { await api.respondConsent(c.id, false); c.status = 'denied'; rerender(['privacy']); } }, t('consent.revoke')) : null))));
      body.append(list);
    },
    media(body) {
      const list = h('div', { class: 'list scroll' });
      const clinicalKinds = ['dicom', 'pdf'];
      state.attachments.forEach(a => {
        const lockedForViewer = mode !== MODES.physician && mode !== MODES.self && clinicalKinds.includes(a.kind);
        list.append(h('div', { class: 'list-item row-between' },
          h('div', {}, h('span', { class: `kind kind-${a.kind}` }, a.kind.toUpperCase()), ' ', h('b', {}, a.name), a.private ? ' 🔒' : '', h('div', { class: 'muted small' }, a.live ? '● LIVE' : formatTime(a.time, { lang: lang() }))),
          lockedForViewer ? h('span', { class: 'muted small' }, t('media.physicianOnly')) : h('button', { class: 'btn sm', onclick: () => openMedia(a) }, t('media.open'))));
      });
      if (!state.attachments.length) list.append(h('p', { class: 'muted' }, t('common.noData')));
      body.append(list);
    },
    ecg(body) {
      const host = h('div', { class: 'ecg-host' }); body.append(host);
      api.measurements(subjectId, 'ecg', queryWindow(1)).then(ms => ecgChart(host, ms[0])).catch(e => host.append(h('p', { class: 'muted' }, e.message)));
    },
    evaluation(body) {
      const assess = h('select', {}, ['ok', 'warn', 'crit'].map(s2 => h('option', { value: s2 }, t('status.' + s2))));
      const note = h('textarea', { rows: 3, placeholder: t('eval.notePh') });
      const notify = h('input', { type: 'checkbox' });
      const form = h('div', { class: 'form compact' }, h('div', { class: 'row' }, h('label', { class: 'field' }, h('span', { class: 'field-label' }, t('eval.assessment')), assess), h('label', { class: 'check' }, notify, h('span', {}, t('eval.notify')))), note,
        h('button', { class: 'btn primary sm', onclick: async () => {
          if (!note.value.trim()) { note.focus(); return; }
          await api.saveEvaluation({ userId: subjectId, assessment: assess.value, note: note.value.trim() });
          if (notify.checked) {
            const teams = await api.listTeams(); const leaderId = teams.find(x => x.id === state.user.teamId)?.leaderId;
            if (leaderId) await api.sendWarning({ toId: leaderId, level: assess.value === 'ok' ? 'info' : assess.value, parameter: null, message: `${t('eval.title')} — ${state.user.name}: ${note.value.trim()}` });
          }
          toast(t('eval.saved'), 'ok');
          state.evaluations = await api.listEvaluations(subjectId); rerender(['evaluation']);
        } }, t('common.save')));
      const list = h('div', { class: 'list scroll short' }, state.evaluations.map(e => h('div', { class: 'list-item' }, h('div', { class: 'li-top' }, statusPill(e.assessment), h('b', {}, e.physicianName), h('span', { class: 'muted small' }, formatTime(e.time, { lang: lang() }))), h('div', { class: 'li-text' }, e.note))));
      body.append(form, list);
    },
  };

  function paramRow(p) {
    const m = latestValues()[p.id]; const ev = m?.v != null ? evaluate(p, m.v) : null;
    return h('button', { class: `prow st-${ev?.status || 'none'}`, onclick: () => openParam(p.id) },
      statusDot(ev?.status || 'none'),
      h('span', { class: 'prow-name' }, paramName(p, lang()), m?.private ? ' 🔒' : ''),
      h('span', { class: 'meter' }, h('i', { style: { width: `${ev?.score ?? 0}%`, background: STATUS_COLOR[ev?.status || 'none'] } })),
      h('span', { class: 'prow-score' }, ev ? (showValues ? `${m.v} ${p.unit}` : ev.score) : m?.locked ? '🔒' : '–'));
  }

  function legend() {
    return h('div', { class: 'legend' }, ['ok', 'warn', 'crit', 'none'].map(st => h('span', {}, statusDot(st), t('status.' + st))));
  }

  function openMedia(a) {
    const body = h('div', { class: 'media-view' });
    if (a.url && (a.kind === 'image')) body.append(h('img', { src: a.url, alt: a.name }));
    else if (a.url && a.kind === 'pdf') body.append(h('iframe', { src: a.url, title: a.name }));
    else if (a.kind === 'camera') { const cv = h('canvas', { width: 640, height: 360, class: 'cam' }); body.append(cv); fakeCamera(cv, state.user.name); }
    else if (a.kind === 'dicom') { const cv = h('canvas', { width: 512, height: 400, class: 'us' }); body.append(cv, h('div', { class: 'muted small' }, t('media.dicomNote'))); fakeUltrasound(cv); }
    else body.append(h('p', { class: 'muted' }, t('media.noPreview')), a.url ? h('a', { href: a.url, target: '_blank', rel: 'noopener' }, t('media.download')) : null);
    modal(a.name, body, { wide: true });
  }

  // ---- lifecycle --------------------------------------------------------------------------------
  const offLang = onLanguageChange(() => { renderHead(); renderGrid(); });
  (async () => {
    grid.append(h('div', { class: 'loading' }, t('common.loading')));
    try { await loadAll(); } catch (e) { clear(grid).append(h('div', { class: 'error' }, e.message)); return; }
    if (destroyed) return;
    renderHead(); renderGrid();
    timers.push(setInterval(refreshLatest, (config.polling.latestSeconds || 15) * 1000));
    if (mode === MODES.self) timers.push(setInterval(refreshInbox, (config.polling.inboxSeconds || 10) * 1000));
  })();

  return {
    destroy() { destroyed = true; timers.forEach(clearInterval); offLang(); },
    refresh: async () => { await loadAll(); renderHead(); renderGrid(); },
    get user() { return state.user; },
    setUser(u) { state.user = u; renderHead(); rerender(['suit', 'map']); },
  };
}

function hashStr(str) { let x = 0; for (const c of str) x = (x * 31 + c.charCodeAt(0)) >>> 0; return x; }

function fakeCamera(cv, name) {
  const g = cv.getContext('2d'); let f = 0;
  const loop = () => {
    if (!cv.isConnected) return;
    const img = g.createImageData(cv.width, cv.height);
    for (let i = 0; i < img.data.length; i += 4) { const v = 20 + Math.random() * 40; img.data[i] = v * 0.6; img.data[i + 1] = v * 0.8; img.data[i + 2] = v; img.data[i + 3] = 255; }
    g.putImageData(img, 0, 0);
    g.strokeStyle = '#4fc3f7'; g.lineWidth = 1; g.strokeRect(20, 20, cv.width - 40, cv.height - 40);
    g.beginPath(); g.moveTo(cv.width / 2 - 20, cv.height / 2); g.lineTo(cv.width / 2 + 20, cv.height / 2); g.moveTo(cv.width / 2, cv.height / 2 - 20); g.lineTo(cv.width / 2, cv.height / 2 + 20); g.stroke();
    g.fillStyle = '#4fc3f7'; g.font = '14px monospace'; g.fillText(`CAM-01  ${name}`, 30, 44); g.fillText(new Date().toISOString().slice(11, 19) + ' UTC', cv.width - 150, 44);
    g.fillStyle = f++ % 60 < 30 ? '#ff4d4f' : 'transparent'; g.beginPath(); g.arc(cv.width - 40, cv.height - 40, 6, 0, 7); g.fill();
    g.fillStyle = '#9fb3d1'; g.fillText('DEMO FEED — no stream URL configured', 30, cv.height - 34);
    setTimeout(() => requestAnimationFrame(loop), 80);
  };
  loop();
}

function fakeUltrasound(cv) {
  const g = cv.getContext('2d'); const W = cv.width, H = cv.height;
  g.fillStyle = '#000'; g.fillRect(0, 0, W, H);
  const img = g.getImageData(0, 0, W, H); const cx = W / 2, top = 20;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const dx = x - cx, dy = y - top, r = Math.hypot(dx, dy), a = Math.atan2(dx, dy);
    if (r > H - 30 || Math.abs(a) > 0.62) continue;
    // speckle + two "chambers"
    let v = Math.random() * 90 * Math.exp(-r / 600);
    const ch = (px, py, rx, ry) => ((x - px) / rx) ** 2 + ((y - py) / ry) ** 2 < 1;
    if (ch(cx - 50, 200, 42, 70) || ch(cx + 50, 205, 40, 66) || ch(cx - 40, 320, 34, 40) || ch(cx + 42, 322, 32, 38)) v *= 0.15;
    const i = (y * W + x) * 4; img.data[i] = img.data[i + 1] = img.data[i + 2] = v * 2; img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  g.fillStyle = '#9fb3d1'; g.font = '12px monospace'; g.fillText('US · 2.5 MHz · DEMO', 10, H - 10);
}
