// =============================================================================
// Ground Control — sees every team and every individual.
//  • roles: operator (scores only) and physician (raw data, ECG, ultrasound/
//    DICOM, PDFs, evaluations)
//  • 3D disks: overall aggregate (one layer per team average + overall
//    average) or per team (one layer per member + team average)
//  • drill-down: all teams → team → individual
//  • warnings to Team Leaders or directly to individuals
// =============================================================================
import { startApp } from '../../common/js/appShell.js';
import { renderTeamView, alertItems } from '../../common/js/views/teamView.js';
import { renderUserDashboard } from '../../common/js/views/userDashboard.js';
import { renderMap } from '../../common/js/components/mapView.js';
import { Disk3D } from '../../common/js/components/disk3d.js';
import { renderDisk } from '../../common/js/components/diskChart.js';
import { h, clear, statusPill, toast, sendWarningDialog } from '../../common/js/ui.js';
import { t, lang, onLanguageChange } from '../../common/js/i18n.js';
import { summarize, averageLatest, readinessStatus, STATUS_COLOR } from '../../common/js/scoring.js';
import { paramName } from '../../common/js/params.js';
import { formatTime, formatDual, relative, zoneLabel } from '../../common/js/time.js';

const TEAM_COLORS = ['#4fc3f7', '#ff9e4f', '#b388ff', '#69f0ae', '#ffd54f', '#f48fb1'];

startApp({
  id: 'ground-control',
  titleKey: 'app.title',
  subtitleKey: 'app.gc',
  allowedRoles: ['operator', 'physician'],
  nav: () => [{ id: 'overview', labelKey: 'nav.overview' }, { id: 'map', labelKey: 'nav.map' }, { id: 'messages', labelKey: 'nav.messages' }],
  sourceZone: () => 'UTC',
  mount(main, ctx) {
    const { api, config, user } = ctx;
    const mode = user.role === 'physician' ? 'physician' : 'operator';
    let view = null, teams = [], everyone = [];
    const close = () => { view?.destroy?.(); view = null; };

    async function loadPeople() {
      teams = await api.listTeams();
      const lists = await Promise.all(teams.map(tm => api.teamMembers(tm.id)));
      everyone = lists.flat();
      teams.forEach((tm, i) => { tm.members = lists[i]; tm.color = TEAM_COLORS[i % TEAM_COLORS.length]; });
    }
    const leaderOf = u => everyone.find(x => x.teamId === u.teamId && x.role === 'teamleader');
    const recipients = u => { const l = leaderOf(u); return l && l.id !== u.id ? [u, l] : [u]; };

    // ---- overview (all teams aggregate) -------------------------------------------------------
    async function showOverview() {
      close();
      await loadPeople();
      let latestById = {}, selected = null, destroyed = false;
      const d3host = h('div', { class: 'd3-host' });
      const selPanel = h('div', { class: 'panel sel-panel' });
      const cards = h('div', { class: 'cards' });
      const alerts = h('div', { class: 'list alerts-list scroll', style: { maxHeight: '420px' } });
      const scopeBar = h('div', { class: 'seg' });
      clear(main).append(
        h('div', { class: 'dash-head' }, h('div', { class: 'who' }, h('div', {}, h('div', { class: 'who-name' }, t('gc.title')), h('div', { class: 'who-sub' }, `${teams.length} ${t('gc.teams')} · ${everyone.length} ${t('team.membersShort')} · ${t('role.' + user.role)}`))), scopeBar),
        h('div', { class: 'layout-2' },
          h('div', { class: 'stack' }, h('div', { class: 'panel' }, h('h3', {}, t('gc.aggregate3d')), h('div', { class: 'd3-controls' }, t('gc.hintAgg')), d3host), selPanel),
          h('div', { class: 'stack' }, h('div', { class: 'panel' }, h('h3', {}, t('gc.teams')), cards), h('div', { class: 'panel' }, h('h3', {}, t('team.alerts')), alerts))));
      scopeBar.append(h('button', { class: 'seg-btn on' }, t('gc.allTeams')), ...teams.map(tm => h('button', { class: 'seg-btn', onclick: () => showTeam(tm) }, tm.name)));

      const disk = new Disk3D(d3host, { onSelect: i => { selected = i; drawSel(); } });
      const layers = () => {
        const L = teams.map(tm => { const avg = averageLatest(tm.members.map(m => latestById[m.id]?.values || {})); return { id: tm.id, name: tm.name, color: tm.color, latest: avg, badge: summarize(avg).readiness, team: tm }; });
        const all = averageLatest(everyone.map(m => latestById[m.id]?.values || {}));
        L.push({ id: 'all', name: t('gc.overall'), color: '#ffffff', latest: all, badge: summarize(all).readiness });
        return L;
      };
      const drawSel = () => {
        clear(selPanel);
        const L = layers()[selected];
        if (!L) { selPanel.append(h('h3', {}, t('team.selectedLayer')), h('p', { class: 'muted' }, t('team.selectHint'))); return; }
        const d = h('div', { class: 'disk-host' }); const sum = summarize(L.latest);
        selPanel.append(h('div', { class: 'row row-between' }, h('h3', {}, `${t('team.selectedLayer')}: ${L.name}`), L.team ? h('button', { class: 'btn sm', onclick: () => showTeam(L.team) }, t('gc.openTeam')) : null), d);
        renderDisk(d, { latest: L.latest, showValues: mode === 'physician', center: { value: sum.readiness ?? '–', status: readinessStatus(sum.readiness), label: t('ready.short') } });
      };
      const drawCards = () => {
        clear(cards);
        teams.forEach(tm => {
          const sum = summarize(averageLatest(tm.members.map(m => latestById[m.id]?.values || {})));
          const crit = tm.members.filter(m => summarize(latestById[m.id]?.values || {}).counts.crit).length;
          cards.append(h('button', { class: 'card', onclick: () => showTeam(tm) },
            h('div', { class: 'card-top' }, h('span', { class: 'd3-dot', style: { background: tm.color, width: '14px', height: '14px' } }),
              h('div', {}, h('div', { class: 'card-name' }, tm.name), h('div', { class: 'card-sub' }, `${t('map.' + tm.frame)} · ${zoneLabel(tm.timezone)} ${formatTime(new Date(), { zone: tm.timezone, withDate: false, lang: lang() })}`)),
              h('div', { class: `card-score st-${readinessStatus(sum.readiness)}` }, sum.readiness ?? '–')),
            h('div', { class: 'mini-bars' }, tm.members.map(m => h('i', { style: { background: STATUS_COLOR[summarize(latestById[m.id]?.values || {}).overall] }, title: m.name }))),
            h('div', { class: 'small muted' }, `${tm.members.length} ${t('team.membersShort')}`, crit ? h('span', { style: { color: 'var(--crit)', marginLeft: '8px' } }, `■ ${crit} ${t('gc.critMembers')}`) : null)));
        });
        clear(alerts);
        const items = alertItems(everyone, latestById, u => showMember(u, teams.find(x => x.id === u.teamId)));
        alerts.append(...(items.length ? items.slice(0, 30) : [h('p', { class: 'muted' }, t('team.noAlerts'))]));
      };
      const load = async () => { const ls = await Promise.all(everyone.map(u => api.latest(u.id).catch(() => null))); latestById = Object.fromEntries(everyone.map((u, i) => [u.id, ls[i]])); };
      await load();
      disk.setLayers(layers()); drawSel(); drawCards();
      const timer = setInterval(async () => { await load(); if (destroyed) return; disk.setLayers(layers()); drawSel(); drawCards(); }, (config.polling.latestSeconds || 15) * 1000);
      const off = onLanguageChange(() => showOverview());
      view = { destroy: () => { destroyed = true; clearInterval(timer); off(); disk.dispose(); } };
    }

    // ---- one team --------------------------------------------------------------------------------------
    function showTeam(tm) {
      close();
      const bar = h('div', { class: 'seg' }, h('button', { class: 'seg-btn', onclick: showOverview }, t('gc.allTeams')), ...teams.map(x => h('button', { class: `seg-btn ${x.id === tm.id ? 'on' : ''}`, onclick: () => showTeam(x) }, x.name)));
      view = renderTeamView(main, {
        api, config, viewer: user, team: tm, mode, recipients, onBack: showOverview,
        members: tm.members,
        onOpenMember: u => showMember(u, tm),
        headerActions: members => {
          const leader = members.find(m => m.role === 'teamleader');
          return [bar, leader ? h('button', { class: 'btn danger', onclick: () => sendWarningDialog(api, { to: leader, recipients: members }) }, '⚠ ' + t('gc.warnLeader')) : null];
        },
      });
    }

    // ---- one person ---------------------------------------------------------------------------------------
    function showMember(u, tm) {
      close();
      view = renderUserDashboard(main, { api, config, viewer: user, subjectId: u.id, mode, teamName: tm?.name, recipients, onBack: () => showTeam(tm) });
      window.scrollTo({ top: 0 });
    }

    // ---- map ------------------------------------------------------------------------------------------------
    async function showMap() {
      close();
      await loadPeople();
      const ls = await Promise.all(everyone.map(u => api.latest(u.id)));
      const host = h('div', { class: 'map-host big' });
      clear(main).append(h('div', { class: 'section-title' }, h('h2', {}, t('nav.map'))), h('div', { class: 'panel' }, host));
      renderMap(host, { frame: 'earth', points: everyone.map((u, i) => ({ ...ls[i].location, label: `${u.name} (${teams.find(x => x.id === u.teamId)?.name})`, short: u.name.split(' ')[0], avatar: u.avatar, group: teams.find(x => x.id === u.teamId)?.name, sub: ls[i].location.module || `${ls[i].location.lat}, ${ls[i].location.lon}`, color: u.color, status: summarize(ls[i].values).overall, time: formatDual(new Date(), ls[i].timezone, lang()), user: u })), onSelect: p => showMember(p.user, teams.find(x => x.id === p.user.teamId)) });
    }

    // ---- messages ------------------------------------------------------------------------------------------
    async function showMessages() {
      close();
      await loadPeople();
      const nameOf = id => everyone.find(m => m.id === id)?.name || id;
      const draw = async () => {
        const [inbox, sent] = await Promise.all([api.inbox(user.id), api.sent(user.id)]);
        const compose = h('button', { class: 'btn danger', onclick: async () => { if (await sendWarningDialog(api, { to: everyone[0], recipients: everyone })) draw(); } }, '⚠ ' + t('msg.compose'));
        const item = (w, out) => h('div', { class: `list-item warn-item lvl-${w.level} ${w.ack ? 'acked' : ''}` },
          h('div', { class: 'li-top' }, statusPill(w.level === 'info' ? 'none' : w.level, t('level.' + w.level)), out ? '→ ' : '', h('b', {}, out ? nameOf(w.toId) : w.fromName), h('span', { class: 'muted small' }, relative(w.time, lang()))),
          w.parameter ? h('div', { class: 'small' }, paramName(w.parameter, lang())) : null, h('div', { class: 'li-text' }, w.message),
          out ? h('div', { class: 'muted small' }, w.ack ? '✓ ' + t('msg.read') : t('msg.unread')) : (w.ack ? null : h('button', { class: 'btn sm', onclick: async () => { await api.ackWarning(w.id); draw(); } }, t('inbox.ack'))));
        clear(main).append(h('div', { class: 'section-title' }, h('h2', {}, t('nav.messages')), compose), h('div', { class: 'layout-2' },
          h('div', { class: 'panel' }, h('h3', {}, t('msg.sent')), sent.length ? h('div', { class: 'list' }, sent.map(w => item(w, true))) : h('p', { class: 'muted' }, t('inbox.empty'))),
          h('div', { class: 'panel' }, h('h3', {}, t('msg.inbox')), inbox.length ? h('div', { class: 'list' }, inbox.map(w => item(w, false))) : h('p', { class: 'muted' }, t('inbox.empty')))));
      };
      await draw();
      const timer = setInterval(draw, (config.polling.inboxSeconds || 10) * 1000);
      const off = onLanguageChange(draw);
      view = { destroy: () => { clearInterval(timer); off(); } };
    }

    showOverview().catch(e => toast(e.message, 'crit'));
    return {
      destroy: close,
      onNav: id => ({ overview: showOverview, map: showMap, messages: showMessages })[id]?.(),
    };
  },
});
