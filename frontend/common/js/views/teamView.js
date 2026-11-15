// =============================================================================
// Team view — 3D stacked disks (one layer per member + team average),
// selected-layer 2D disk, member cards and an alert list.
// Used by Team Leader (own team) and Ground Control (any team).
// =============================================================================
import { h, clear, avatar, statusPill, toast, sendWarningDialog } from '../ui.js';
import { t, lang, onLanguageChange } from '../i18n.js';
import { paramName } from '../params.js';
import { summarize, readinessStatus, averageLatest, STATUS_COLOR } from '../scoring.js';
import { formatTime, zoneLabel } from '../time.js';
import { Disk3D } from '../components/disk3d.js';
import { renderDisk } from '../components/diskChart.js';

export function memberCard(u, latest, { onClick, selected } = {}) {
  const sum = summarize(latest?.values || {});
  const st = readinessStatus(sum.readiness);
  const locked = Object.values(latest?.values || {}).filter(v => v.locked).length;
  const bars = sum.items.filter(i => !i.param.env).map(i => h('i', { style: { background: STATUS_COLOR[i.status] }, title: paramName(i.param, lang()) }));
  return h('button', { class: `card ${selected ? 'sel' : ''}`, onclick: onClick },
    h('div', { class: 'card-top' }, avatar(u, 36), h('div', {}, h('div', { class: 'card-name' }, u.name), h('div', { class: 'card-sub' }, t('role.' + u.role), latest ? ` · ${zoneLabel(latest.timezone)} ${formatTime(new Date(), { zone: latest.timezone, withDate: false, lang: lang() })}` : '')),
      h('div', { class: `card-score st-${st}` }, sum.readiness ?? '–')),
    h('div', { class: 'mini-bars' }, bars),
    h('div', { class: 'counts small' }, h('span', { class: 'c-ok' }, `● ${sum.counts.ok}`), h('span', { class: 'c-warn' }, `▲ ${sum.counts.warn}`), h('span', { class: 'c-crit' }, `■ ${sum.counts.crit}`), locked ? h('span', { class: 'muted' }, `🔒 ${locked}`) : null));
}

export function alertItems(members, latestById, onOpen) {
  const out = [];
  for (const u of members) {
    const sum = summarize(latestById[u.id]?.values || {});
    sum.items.filter(i => i.status !== 'ok').forEach(i => out.push({ u, i }));
  }
  out.sort((a, b) => (a.i.status === 'crit' ? 0 : 1) - (b.i.status === 'crit' ? 0 : 1) || a.i.score - b.i.score);
  return out.map(({ u, i }) => h('div', { class: 'list-item', onclick: () => onOpen(u, i.param.id) },
    statusPill(i.status), avatar(u, 22), h('b', {}, u.name), h('span', {}, paramName(i.param, lang())), h('span', { class: 'muted small', style: { marginLeft: 'auto' } }, `${i.score}/100`)));
}

/**
 * @param ctx { api, config, viewer, team, mode, onOpenMember(u), recipients(u), title }
 */
export function renderTeamView(host, ctx) {
  const { api, config, team } = ctx;
  let members = [], latestById = {}, disk = null, selected = null, includeAvg = true, timer = null, destroyed = false;

  const root = h('div', { class: 'team-view' }); clear(host).append(root);
  const headEl = h('div', { class: 'dash-head' });
  const d3host = h('div', { class: 'd3-host' });
  const controls = h('div', { class: 'd3-controls' });
  const selPanel = h('div', { class: 'panel sel-panel' });
  const cards = h('div', { class: 'cards' });
  const alerts = h('div', { class: 'list alerts-list scroll' });
  root.append(headEl,
    h('div', { class: 'layout-2' },
      h('div', { class: 'stack' }, h('div', { class: 'panel' }, h('h3', {}, t('team.disk3d')), controls, d3host), selPanel),
      h('div', { class: 'stack' }, h('div', { class: 'panel' }, h('h3', {}, t('team.members')), cards), h('div', { class: 'panel' }, h('h3', {}, t('team.alerts')), alerts))));

  const layers = () => {
    const L = members.map(u => ({ id: u.id, name: u.name, color: u.color, avatar: u.avatar, latest: latestById[u.id]?.values || {}, badge: summarize(latestById[u.id]?.values || {}).readiness, user: u }));
    if (includeAvg) {
      const avg = averageLatest(members.map(u => latestById[u.id]?.values || {}).map(v => Object.fromEntries(Object.entries(v).filter(([, x]) => x.v != null))));
      L.push({ id: 'avg', name: t('team.average'), color: '#ffffff', latest: avg, badge: summarize(avg).readiness, avg: true });
    }
    return L;
  };

  function renderHead() {
    clear(headEl);
    const all = summarize(averageLatest(members.map(u => latestById[u.id]?.values || {})));
    headEl.append(h('div', { class: 'who' },
      ctx.onBack ? h('button', { class: 'btn ghost sm', onclick: ctx.onBack }, '← ' + t('common.back')) : null,
      h('div', {}, h('div', { class: 'who-name' }, ctx.title || team.name), h('div', { class: 'who-sub' }, `${t('map.' + team.frame)} · ${zoneLabel(team.timezone)} ${formatTime(new Date(), { zone: team.timezone, withDate: false, lang: lang() })} · ${members.length} ${t('team.membersShort')}`)),
      statusPill(readinessStatus(all.readiness), `${t('team.avgReadiness')}: ${all.readiness ?? '–'}`)),
      h('div', { class: 'dash-actions' }, ctx.headerActions?.(members) || null));
  }

  function renderControls() {
    clear(controls);
    const gap = h('input', { type: 'range', min: 0.6, max: 5, step: 0.1, value: disk?.gap ?? 2.2 });
    gap.addEventListener('input', () => disk?.setGap(Number(gap.value)));
    const avg = h('input', { type: 'checkbox', checked: includeAvg });
    avg.addEventListener('change', () => { includeAvg = avg.checked; disk?.setLayers(layers()); });
    const layerSel = h('select', { class: 'sm' }, h('option', { value: '' }, t('team.allLayers')), layers().map((l, i) => h('option', { value: i, selected: selected === i }, l.name)));
    layerSel.addEventListener('change', () => disk?.setSelected(layerSel.value === '' ? selected : Number(layerSel.value)));
    controls.append(h('label', { class: 'row' }, t('team.layer'), layerSel), h('label', { class: 'row' }, t('team.spacing'), gap), h('label', { class: 'row' }, avg, t('team.showAverage')), h('span', { class: 'muted' }, t('team.hint3d')));
  }

  function renderSel() {
    clear(selPanel);
    const L = layers()[selected];
    if (!L) { selPanel.append(h('h3', {}, t('team.selectedLayer')), h('p', { class: 'muted' }, t('team.selectHint'))); return; }
    const sum = summarize(L.latest);
    const d = h('div', { class: 'disk-host' });
    selPanel.append(h('div', { class: 'row-between row' }, h('h3', {}, `${t('team.selectedLayer')}: ${L.name}`),
      L.user ? h('div', { class: 'row' }, h('button', { class: 'btn sm', onclick: () => ctx.onOpenMember(L.user) }, t('team.openProfile')),
        h('button', { class: 'btn sm danger', onclick: () => sendWarningDialog(api, { to: L.user, recipients: ctx.recipients?.(L.user) }) }, '⚠ ' + t('warn.title'))) : null), d);
    renderDisk(d, { latest: L.latest, showValues: ctx.mode === 'physician', center: { value: sum.readiness ?? '–', status: readinessStatus(sum.readiness), label: t('ready.short') }, onSelect: L.user ? () => ctx.onOpenMember(L.user) : null });
  }

  function renderCards() {
    clear(cards);
    members.forEach((u, i) => cards.append(memberCard(u, latestById[u.id], { selected: selected === i, onClick: () => ctx.onOpenMember(u) })));
    clear(alerts);
    const items = alertItems(members, latestById, (u) => ctx.onOpenMember(u));
    if (!items.length) alerts.append(h('p', { class: 'muted' }, t('team.noAlerts'))); else alerts.append(...items);
  }

  async function load() {
    members = ctx.members || await api.teamMembers(team.id);
    const ls = await Promise.all(members.map(u => api.latest(u.id).catch(() => null)));
    latestById = Object.fromEntries(members.map((u, i) => [u.id, ls[i]]));
  }

  function renderAll() {
    renderHead(); renderControls(); renderSel(); renderCards();
    if (!disk) {
      try { disk = new Disk3D(d3host, { onSelect: i => { selected = i; renderSel(); renderCards(); renderControls(); } }); }
      catch (e) { d3host.append(h('p', { class: 'muted pad' }, 'WebGL: ' + e.message)); }
    }
    disk?.setLayers(layers());
  }

  const offLang = onLanguageChange(() => renderAll());
  (async () => {
    try { await load(); } catch (e) { toast(e.message, 'crit'); return; }
    if (destroyed) return;
    renderAll();
    timer = setInterval(async () => {
      try { await load(); if (destroyed) return; renderHead(); renderSel(); renderCards(); disk?.setLayers(layers()); } catch (e) { console.warn(e); }
    }, (config.polling.latestSeconds || 15) * 1000);
  })();

  return {
    destroy() { destroyed = true; clearInterval(timer); offLang(); disk?.dispose(); },
    get members() { return members; },
    get latestById() { return latestById; },
  };
}
