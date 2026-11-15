// =============================================================================
// Config loader. Every project has its own ./config.json (server URL,
// endpoints, mode, polling, privacy flags). Missing keys fall back to DEFAULTS.
// =============================================================================

export const DEFAULTS = {
  app: 'unknown',
  mode: 'mock',                 // 'live' | 'mock' | 'auto' (auto = live, mock if server unreachable)
  defaultLanguage: 'en',
  server: {
    baseUrl: 'http://localhost/spacehealth/api',
    timeoutMs: 10000,
    apiKey: '',
    withCredentials: false,
  },
  endpoints: {
    login: 'auth/login.php',
    logout: 'auth/logout.php',
    me: 'users/me.php',
    user: 'users/get.php',
    userSettings: 'users/settings.php',
    teams: 'teams/list.php',
    teamMembers: 'teams/members.php',
    latest: 'measurements/latest.php',
    measurements: 'measurements/list.php',
    upload: 'measurements/upload.php',
    attachments: 'measurements/attachments.php',
    journalList: 'journal/list.php',
    journalAdd: 'journal/add.php',
    questionnaires: 'questionnaires/list.php',
    questionnaireSubmit: 'questionnaires/submit.php',
    warningSend: 'warnings/send.php',
    warningInbox: 'warnings/inbox.php',
    warningAck: 'warnings/ack.php',
    warningSent: 'warnings/sent.php',
    consentRequest: 'consent/request.php',
    consentRespond: 'consent/respond.php',
    consentList: 'consent/list.php',
    evaluationSave: 'evaluations/save.php',
    evaluationList: 'evaluations/list.php',
  },
  polling: { latestSeconds: 15, inboxSeconds: 10 },
  privacy: { showRawValuesToNonPhysicians: false },
  history: { defaultHours: 24 },
};

function deepMerge(a, b) {
  if (Array.isArray(b) || typeof b !== 'object' || b === null) return b ?? a;
  const out = { ...a };
  for (const k of Object.keys(b)) out[k] = (typeof a?.[k] === 'object' && !Array.isArray(a[k])) ? deepMerge(a[k], b[k]) : b[k];
  return out;
}

export async function loadConfig(url = './config.json') {
  try {
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) throw new Error(res.status);
    return deepMerge(DEFAULTS, await res.json());
  } catch (e) {
    console.warn('[config] could not load', url, '— using defaults', e);
    return structuredClone(DEFAULTS);
  }
}
