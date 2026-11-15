// =============================================================================
// i18n — UI languages: the ISS working languages (English, Russian) and the
// partner-agency languages (Japanese, French, German, Italian) + Hungarian.
// Missing keys fall back to English, then to the key itself.
// =============================================================================
import { LOCALES } from './locales.js';

export const LANGUAGES = [
  { code: 'en', label: 'English' },
  { code: 'ru', label: 'Русский' },
  { code: 'ja', label: '日本語' },
  { code: 'fr', label: 'Français' },
  { code: 'de', label: 'Deutsch' },
  { code: 'it', label: 'Italiano' },
  { code: 'hu', label: 'Magyar' },
];

let current = 'en';
const listeners = new Set();

export function initLanguage(preferred, fallback = 'en') {
  const saved = localStorage.getItem('shm_lang');
  const nav = (navigator.language || 'en').slice(0, 2);
  const pick = [preferred, saved, nav, fallback].find(c => c && LOCALES[c]);
  setLanguage(pick || 'en', { silent: true });
  return current;
}

export function setLanguage(code, { silent = false } = {}) {
  if (!LOCALES[code]) return;
  current = code;
  localStorage.setItem('shm_lang', code);
  document.documentElement.lang = code;
  applyStatic();
  if (!silent) listeners.forEach(fn => fn(code));
}

export function lang() { return current; }
export function onLanguageChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }

export function t(key, vars) {
  let s = LOCALES[current]?.[key] ?? LOCALES.en[key] ?? key;
  if (vars) s = s.replace(/\{(\w+)\}/g, (_, k) => (vars[k] ?? `{${k}}`));
  return s;
}

/** Translate static markup: <span data-i18n="key">, data-i18n-title, data-i18n-placeholder */
export function applyStatic(root = document) {
  root.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
  root.querySelectorAll('[data-i18n-title]').forEach(el => { el.title = t(el.dataset.i18nTitle); });
  root.querySelectorAll('[data-i18n-placeholder]').forEach(el => { el.placeholder = t(el.dataset.i18nPlaceholder); });
}
