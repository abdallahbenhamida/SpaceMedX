# PHP server API contract (client side v0.1)

The PHP server already exists — this document describes **what the browser clients request**, so the server side can be matched to it.
All paths are configurable in each project's `config.json` (`endpoints`), relative to `server.baseUrl`.

## General rules

| Topic | Rule |
|---|---|
| Format | Request bodies and responses are JSON (`Content-Type: application/json`). Optional envelope: `{ "ok": true, "data": … }` / `{ "ok": false, "error": "…" }` — the client unwraps it automatically. |
| Auth | `POST auth/login.php` returns a token; every further request sends `Authorization: Bearer <token>` (and `X-API-Key` if `server.apiKey` is set). |
| Time | Every timestamp is **ISO‑8601 with an offset** (`2026-11-14T10:00:00Z` or `…+01:00`). Query windows are sent in UTC (`from`, `to`) together with the viewer's IANA zone (`tz`). Each data source declares its own zone in `source.timezone` (`UTC` for the ISS, `LTC` for a lunar base, `Europe/Budapest`, …). |
| Roles | `user`, `teamleader`, `operator` (Ground Control, non-medical), `physician` (Ground Control). |
| Private data | Values flagged `private` must **not** be sent to a team leader / operator unless the owner granted consent (`consent/*`). Return them as `{ "v": null, "private": true, "locked": true }` (or `403` with `"error":"consent-required"` on `measurements/list.php`). Physicians and the owner always see them. **The server must enforce this — the client only displays.** |

## Endpoints

| Key in config | Method | Path (default) | Parameters / body | Response |
|---|---|---|---|---|
| login | POST | `auth/login.php` | `{ username, password, app }` | `{ token, user }` |
| logout | POST | `auth/logout.php` | `{}` | `{ ok }` |
| user | GET | `users/get.php` | `id` | `User` |
| userSettings | POST | `users/settings.php` | `{ userId, color?, language?, avatar? }` — `avatar`: profile picture as a JPEG data URL (≈192×192 px, ~10–20 kB) or `null` to remove | `{ ok }` |
| teams | GET | `teams/list.php` | – | `Team[]` |
| teamMembers | GET | `teams/members.php` | `teamId` | `User[]` |
| latest | GET | `measurements/latest.php` | `userId` | `Latest` |
| measurements | GET | `measurements/list.php` | `userId, parameter, from, to, tz` | `Measurement[]` (for `parameter=ecg`: `[Waveform]`) |
| upload | POST | `measurements/upload.php` | `Measurement` (one JSON = one measurement) | `{ ok, stored }` |
| attachments | GET | `measurements/attachments.php` | `userId` | `Attachment[]` |
| journalList | GET | `journal/list.php` | `userId, from?, to?` | `JournalEntry[]` |
| journalAdd | POST | `journal/add.php` | `JournalEntry` | `JournalEntry` |
| questionnaires | GET | `questionnaires/list.php` | – | `Questionnaire[]` |
| questionnaireSubmit | POST | `questionnaires/submit.php` | `{ userId, questionnaireId, time, timezone, answers, derived?, private }` | `{ ok }` |
| warningSend | POST | `warnings/send.php` | `{ toId, level: info\|warn\|crit, parameter?, message }` (sender = token owner) | `Warning` |
| warningInbox | GET | `warnings/inbox.php` | `userId` | `Warning[]` |
| warningSent | GET | `warnings/sent.php` | `userId` | `Warning[]` |
| warningAck | POST | `warnings/ack.php` | `{ id }` | `{ ok }` |
| consentRequest | POST | `consent/request.php` | `{ ownerId, scope: "all-private", reason }` | `Consent` |
| consentRespond | POST | `consent/respond.php` | `{ id, granted: bool }` (only the owner) | `{ ok }` |
| consentList | GET | `consent/list.php` | `userId` (as owner or requester) | `Consent[]` |
| evaluationSave | POST | `evaluations/save.php` | `{ userId, assessment: ok\|warn\|crit, note }` (physician only) | `Evaluation` |
| evaluationList | GET | `evaluations/list.php` | `userId` | `Evaluation[]` |

Allowed warning directions: Team Leader → own members; Ground Control → Team Leaders and any user.

## Data shapes

### Measurement (upload unit — one `.json` file = one user's one measurement)

```json
{
  "schemaVersion": "1.0",
  "measurementId": "m-u102-hr-20261114-1200",
  "userId": "u-102",
  "parameter": "heartRate",
  "unit": "bpm",
  "type": "series",
  "private": false,
  "source": {
    "device": "Smart suit v2",
    "timezone": "LTC",
    "location": { "frame": "moon", "lat": -89.41, "lon": -137.6 }
  },
  "samples": [ { "t": "2026-11-14T12:00:00Z", "v": 92 }, { "t": "2026-11-14T12:05:00Z", "v": 95 } ],
  "attachments": [ { "kind": "dicom", "name": "Cardiac ultrasound", "url": "https://…/us.dcm" } ],
  "meta": { "activity": "post-EVA rest" }
}
```

* `type`: `single` (one sample, e.g. a lab value) or `series` (continuous stream).
* `parameter` must be an id from `common/js/params.js` (units and healthy/warning ranges are defined there).
* `source.location.frame`: `earth` (`lat`,`lon`), `station` (`module`,`x`,`y` metres in the module), `moon` (`lat`,`lon` selenographic).
* `attachments[].kind`: `dicom`, `image`, `pdf`, `camera` (stream URL), `csv`.
* A JSON array of measurements in one file is also accepted by the client.

See `samples/` for complete examples.

### Latest

```json
{ "userId": "u-102", "timezone": "LTC", "frame": "moon",
  "location": { "frame": "moon", "lat": -89.41, "lon": -137.6 },
  "locationTime": "2026-11-14T12:55:00Z",
  "comm": { "lastContact": "2026-11-14T12:55:00Z", "unackedWarnings": 1, "oldestUnackedAt": "2026-11-14T12:10:00Z" },
  "values": { "heartRate": { "v": 82, "t": "2026-11-14T12:55:00Z", "private": false },
              "moodScore": { "v": null, "t": "…", "private": true, "locked": true } } }
```

* `locationTime` — time of the newest personal measurement that carried `source.location` (null = no position data). Drives the **Location status** (OK ≤ 15 min, warning ≤ 60 min).
* `comm` — `lastContact` is the newest data the person produced (personal measurement, journal entry, questionnaire, warning acknowledgement — habitat telemetry does not count); `unackedWarnings` / `oldestUnackedAt` describe warnings sent to the person and not yet acknowledged. Drives the **Communication status** (OK ≤ 10 min, warning ≤ 60 min; a warning unacknowledged for > 30 min also lowers it).
* Mission readiness = weighted mean of five category statuses (`scoring.js`): Health 35 %, Mental health 20 %, Environmental 20 % (space radiation, gravity fields, habitat), Location 10 %, Communication 15 %; any critical category caps it at 45.
* New parameters: `gravity` (g), `reducedGravityDays`, `isolationDays` (days), `confinementStress` (0–9, from the weekly `confinement` questionnaire).

### Other objects

* `User`: `{ id, name, role, teamId, color, language, avatar }` — `avatar` may be a data URL or an image URL served by the PHP server
* `Team`: `{ id, name, frame, timezone, base, leaderId, memberIds }`
* `JournalEntry`: `{ id, userId, name, time, timezone, meta: {…}, text, private }` — **name, time, metadata are mandatory.**
* `Warning`: `{ id, fromId, fromName, toId, level, parameter, message, time, ack }`
* `Consent`: `{ id, requesterId, requesterName, ownerId, scope, reason, status: pending|granted|denied, time }`
* `Waveform` (ECG): `{ userId, parameter: "ecg", unit: "mV", sampleRate, start, values: [] }`
