// =============================================================================
// Single User — the crew member's own, simplified dashboard.
//  • own data as tiles, "+" adds new data tiles (layout saved per user)
//  • gamified scores / colours instead of raw medical values
//  • upload (JSON or manual), mark as private; journal; questionnaires
//  • warning inbox (from Team Leader / Ground Control)
//  • privacy: grant / deny / revoke Team Leader access to private data
//  • own colour (top bar colour picker)
// =============================================================================
import { startApp } from '../../common/js/appShell.js';
import { renderUserDashboard } from '../../common/js/views/userDashboard.js';

let latestZone = null;

startApp({
  id: 'single-user',
  titleKey: 'app.title',
  subtitleKey: 'app.single',
  allowedRoles: ['user', 'teamleader'],
  ownColor: true,
  sourceZone: () => latestZone,
  mount(main, ctx) {
    const { api, user } = ctx;
    api.latest(user.id).then(l => { latestZone = l.timezone; ctx.redrawTop(); }).catch(() => {});
    const dash = renderUserDashboard(main, { api, config: ctx.config, viewer: user, subjectId: user.id, mode: 'self' });
    return {
      destroy: () => dash.destroy(),
      onUserChange: u => dash.setUser({ ...dash.user, color: u.color, avatar: u.avatar }),
    };
  },
});
