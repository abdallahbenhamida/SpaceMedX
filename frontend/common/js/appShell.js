// =============================================================================
// App shell shared by the three projects: config → language → API → login →
// top bar (brand, navigation, clocks, language, own colour, logout) → app.
// =============================================================================
import { loadConfig } from './config.js';
import { createApi } from './api.js';
import { initLanguage, t, onLanguageChange, applyStatic } from './i18n.js';
import { h, clear, loginScreen, languageSelect, colorPicker, clocks, avatar, modeBadge, toast, profilePhotoDialog } from './ui.js';

/**
 * @param {object} app
 *   id, titleKey, subtitleKey
 *   allowedRoles   roles that may log in
 *   nav(ctx)       → [{ id, labelKey }]   (optional)
 *   mount(main, ctx) → { destroy?, onNav? }
 *   sourceZone(ctx) → zone shown in the clock strip (optional)
 */
export async function startApp(app) {
  const config = await loadConfig('./config.json');
  config.app = config.app === 'unknown' ? app.id : config.app;
  initLanguage(null, config.defaultLanguage);
  const api = createApi(config);
  const root = document.getElementById('app');

  const showLogin = () => loginScreen(root, api, {
    appTitleKey: app.titleKey, subtitleKey: app.subtitleKey,
    onLogin: user => {
      if (app.allowedRoles && !app.allowedRoles.includes(user.role)) { api.logout(); toast(t('login.roleDenied'), 'crit'); return showLogin(); }
      boot(user);
    },
  });

  let current = null, offLang = null;
  function boot(user) {
    if (user.language) initLanguage(user.language);
    clear(root);
    const ctx = { api, config, user, app };
    const top = h('header', { class: 'topbar' });
    const main = h('main');
    root.append(top, main);

    const drawTop = () => {
      clear(top);
      const nav = app.nav ? h('nav', {}, app.nav(ctx).map(n => h('button', { class: `nav-btn ${ctx.navActive === n.id ? 'on' : ''}`, onclick: () => { ctx.navActive = n.id; drawTop(); current?.onNav?.(n.id); } }, t(n.labelKey)))) : null;
      top.append(...[
        h('div', { class: 'brand' }, h('span', { class: 'brand-mark' }), h('div', {}, h('div', { class: 'brand-name' }, t(app.titleKey)), h('div', { class: 'brand-sub' }, t(app.subtitleKey)))),
        modeBadge(api), nav, h('div', { class: 'spacer' }),
        clocks(() => app.sourceZone?.(ctx)),
        languageSelect(),
        h('div', { class: 'me' },
          app.ownColor ? colorPicker(user, async c => { user.color = c; await api.saveUserSettings(user.id, { color: c }); current?.onUserChange?.(user); drawTop(); toast(t('user.colorSaved'), 'ok'); }) : null,
          h('button', { class: 'avatar-btn', title: t('photo.title'), onclick: async () => {
            const v = await profilePhotoDialog(api, user);
            if (v === undefined) return;
            user.avatar = v; current?.onUserChange?.(user); drawTop();
          } }, avatar(user, 30)), h('div', { class: 'small' }, h('div', {}, user.name), h('div', { class: 'muted' }, t('role.' + user.role)))),
        h('button', { class: 'btn ghost sm', onclick: async () => { current?.destroy?.(); offLang?.(); await api.logout(); showLogin(); } }, t('login.logout'))].filter(Boolean));
    };
    ctx.navActive = app.nav?.(ctx)?.[0]?.id;
    ctx.redrawTop = drawTop;
    drawTop();
    offLang?.();
    offLang = onLanguageChange(async code => { drawTop(); applyStatic(); try { await api.saveUserSettings(user.id, { language: code }); } catch { /* ignore */ } });
    current = app.mount(main, ctx);
  }

  const existing = await api.currentUser?.();
  if (existing && (!app.allowedRoles || app.allowedRoles.includes(existing.role))) boot(existing); else showLogin();
}
