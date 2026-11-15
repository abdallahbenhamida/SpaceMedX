// =============================================================================
// Team Leader — sees the members of his/her own team.
//  • 3D stacked disks: one layer per member (+ team average), selectable layer
//  • member cards & alert list → member profile (scores only, gamified)
//  • send warning to a member; request consent for private data
//  • team map; messages (inbox from Ground Control, sent warnings)
// =============================================================================
import { startApp } from '../../common/js/appShell.js';
import { renderTeamView } from '../../common/js/views/teamView.js';
import { renderUserDashboard } from '../../common/js/views/userDashboard.js';
import { renderMap } from '../../common/js/components/mapView.js';
import { h, clear, statusPill } from '../../common/js/ui.js';
import { t, lang, onLanguageChange } from '../../common/js/i18n.js';
import { summarize } from '../../common/js/scoring.js';
import { paramName } from '../../common/js/params.js';
import { relative, formatDual } from '../../common/js/time.js';

let teamZone = null;

startApp({
  id: 'team-leader',
  titleKey: 'app.title',
  subtitleKey: 'app.leader',
  allowedRoles: ['teamleader'],
  nav: () => [{ id: 'team', labelKey: 'nav.team' }, { id: 'map', labelKey: 'nav.map' }, { id: 'messages', labelKey: 'nav.messages' }],
  sourceZone: () => teamZone,
  mount(main, ctx) {
    const { api, config, user } = ctx;
    let view = null, team = null;

    const recipients = u => [u];
    const close = () => { view?.destroy?.(); view = null; };

    async function showTeam() {
      close();
      const teams = await api.listTeams();
      team = teams.find(x => x.id === user.teamId);
      teamZone = team?.timezone; ctx.redrawTop();
      if (!team) { clear(main).append(h('p', { class: 'muted' }, t('team.none'))); return; }
      view = renderTeamView(main, { api, config, viewer: user, team, mode: 'leader', recipients, onOpenMember: showMember });
    }

    function showMember(u) {
      close();
      view = renderUserDashboard(main, { api, config, viewer: user, subjectId: u.id, mode: 'leader', teamName: team?.name, recipients, onBack: showTeam });
      window.scrollTo({ top: 0 });
    }

    async function showMap() {
      close();
      const members = await api.teamMembers(user.teamId);
      const ls = await Promise.all(members.map(m => api.latest(m.id)));
      const host = h('div', { class: 'map-host big' });
      clear(main).append(h('div', { class: 'section-title' }, h('h2', {}, t('nav.map'))), h('div', { class: 'panel' }, host));
      renderMap(host, { frame: ls[0]?.frame, points: members.map((m, i) => ({ ...ls[i].location, label: m.name, short: m.name.split(' ')[0], avatar: m.avatar, group: team?.name, sub: ls[i].location.module || `${ls[i].location.lat}, ${ls[i].location.lon}`, color: m.color, status: summarize(ls[i].values).overall, time: formatDual(new Date(), ls[i].timezone, lang()), user: m })), onSelect: p => showMember(p.user) });
    }

    async function showMessages() {
      close();
      const draw = async () => {
        const [inbox, sent, members] = await Promise.all([api.inbox(user.id), api.sent(user.id), api.teamMembers(user.teamId)]);
        const nameOf = id => members.find(m => m.id === id)?.name || id;
        const box = (title, items, render) => h('div', { class: 'panel' }, h('h3', {}, title), items.length ? h('div', { class: 'list' }, items.map(render)) : h('p', { class: 'muted' }, t('inbox.empty')));
        clear(main).append(h('div', { class: 'section-title' }, h('h2', {}, t('nav.messages'))), h('div', { class: 'layout-2' },
          box(t('msg.inbox'), inbox, w => h('div', { class: `list-item warn-item lvl-${w.level} ${w.ack ? 'acked' : ''}` },
            h('div', { class: 'li-top' }, statusPill(w.level === 'info' ? 'none' : w.level, t('level.' + w.level)), h('b', {}, w.fromName), h('span', { class: 'muted small' }, relative(w.time, lang()))),
            w.parameter ? h('div', { class: 'small' }, paramName(w.parameter, lang())) : null, h('div', { class: 'li-text' }, w.message),
            w.ack ? h('div', { class: 'muted small' }, '✓ ' + t('inbox.acked')) : h('button', { class: 'btn sm', onclick: async () => { await api.ackWarning(w.id); draw(); } }, t('inbox.ack')))),
          box(t('msg.sent'), sent, w => h('div', { class: `list-item warn-item lvl-${w.level} ${w.ack ? 'acked' : ''}` },
            h('div', { class: 'li-top' }, statusPill(w.level === 'info' ? 'none' : w.level, t('level.' + w.level)), '→ ', h('b', {}, nameOf(w.toId)), h('span', { class: 'muted small' }, relative(w.time, lang()))),
            h('div', { class: 'li-text' }, w.message), h('div', { class: 'muted small' }, w.ack ? '✓ ' + t('msg.read') : t('msg.unread'))))));
      };
      await draw();
      const timer = setInterval(draw, (config.polling.inboxSeconds || 10) * 1000);
      const off = onLanguageChange(draw);
      view = { destroy: () => { clearInterval(timer); off(); } };
    }

    showTeam();
    return {
      destroy: close,
      onNav: id => ({ team: showTeam, map: showMap, messages: showMessages })[id]?.(),
    };
  },
});

