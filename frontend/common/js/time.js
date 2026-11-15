// =============================================================================
// Time-zone handling.
// All timestamps travel as ISO-8601 in UTC ("...Z") or with an explicit offset.
// Every data source also declares its own zone (source.timezone): an IANA name
// (Europe/Budapest), "UTC" (ISS runs on GMT/UTC) or a lunar zone ("LTC" =
// Coordinated Lunar Time, mapped to UTC until an official offset exists).
// The client always shows the viewer's local time and, on request, the
// source's local time.
// =============================================================================

export const SPECIAL_ZONES = {
  LTC: { label: 'LTC (Lunar)', iana: 'UTC', note: 'Coordinated Lunar Time — displayed as UTC' },
  GMT: { label: 'GMT (ISS)', iana: 'UTC' },
  ISS: { label: 'GMT (ISS)', iana: 'UTC' },
};

export function viewerZone() {
  try { return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'; } catch { return 'UTC'; }
}

export function toIana(zone) {
  if (!zone) return 'UTC';
  if (SPECIAL_ZONES[zone]) return SPECIAL_ZONES[zone].iana;
  try { new Intl.DateTimeFormat('en', { timeZone: zone }); return zone; } catch { return 'UTC'; }
}

export function zoneLabel(zone) {
  return SPECIAL_ZONES[zone]?.label || zone || 'UTC';
}

/** Parse an ISO timestamp; strings without offset are interpreted in `zone`. */
export function parseTime(t, zone = 'UTC') {
  if (t instanceof Date) return t;
  if (typeof t === 'number') return new Date(t);
  if (!t) return null;
  if (/[zZ]|[+-]\d\d:?\d\d$/.test(t)) return new Date(t);
  // No offset: compute the zone's offset at that wall-clock time.
  const asUtc = new Date(t + 'Z');
  const off = zoneOffsetMinutes(toIana(zone), asUtc);
  return new Date(asUtc.getTime() - off * 60000);
}

/** Offset (minutes) of an IANA zone from UTC at a given instant. */
export function zoneOffsetMinutes(zone, date = new Date()) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: zone, hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const parts = Object.fromEntries(dtf.formatToParts(date).map(p => [p.type, p.value]));
  const asUtc = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
  return Math.round((asUtc - date.getTime()) / 60000);
}

export function fmtOffset(mins) {
  const s = mins >= 0 ? '+' : '-', a = Math.abs(mins);
  return `UTC${s}${String(Math.floor(a / 60)).padStart(2, '0')}:${String(a % 60).padStart(2, '0')}`;
}

export function formatTime(t, { zone, lang = 'en', withDate = true, seconds = false } = {}) {
  const d = parseTime(t);
  if (!d || isNaN(d)) return '–';
  const opts = { hour: '2-digit', minute: '2-digit', timeZone: toIana(zone || viewerZone()) };
  if (seconds) opts.second = '2-digit';
  if (withDate) Object.assign(opts, { year: 'numeric', month: '2-digit', day: '2-digit' });
  try { return new Intl.DateTimeFormat(lang, opts).format(d); } catch { return d.toISOString(); }
}

/** "viewer-local (source-local zone)" — used wherever data comes from elsewhere. */
export function formatDual(t, sourceZone, lang) {
  const local = formatTime(t, { lang });
  if (!sourceZone || toIana(sourceZone) === toIana(viewerZone())) return local;
  return `${local} · ${formatTime(t, { zone: sourceZone, lang, withDate: false })} ${zoneLabel(sourceZone)}`;
}

export function relative(t, lang = 'en') {
  const d = parseTime(t); if (!d) return '';
  const diff = (d.getTime() - Date.now()) / 1000;
  const rtf = new Intl.RelativeTimeFormat(lang, { numeric: 'auto' });
  const a = Math.abs(diff);
  if (a < 60) return rtf.format(Math.round(diff), 'second');
  if (a < 3600) return rtf.format(Math.round(diff / 60), 'minute');
  if (a < 86400) return rtf.format(Math.round(diff / 3600), 'hour');
  return rtf.format(Math.round(diff / 86400), 'day');
}

/** Build the UTC query window sent to the server (server may live elsewhere). */
export function queryWindow(hoursBack = 24, to = new Date()) {
  const from = new Date(to.getTime() - hoursBack * 3600 * 1000);
  return { from: from.toISOString(), to: to.toISOString(), tz: viewerZone() };
}

/** datetime-local input value (wall clock in zone) → ISO UTC string. */
export function localInputToIso(value, zone) {
  return parseTime(value.length === 16 ? value + ':00' : value, zone).toISOString();
}

export function nowInputValue(zone = viewerZone()) {
  const d = new Date(Date.now() + zoneOffsetMinutes(toIana(zone)) * 60000);
  return d.toISOString().slice(0, 16);
}
