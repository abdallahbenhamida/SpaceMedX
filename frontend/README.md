# Crew Health Monitor — Visualization (v0.2)

Browser-based health monitoring UI for space crews with three access levels, built from the
`Visualization_Requirements_VM01.xlsx` requirements specification.

```
frontend/
├── single-user/      level 1 – the crew member's own, simplified console
├── team-leader/      level 2 – team leader: 3D disks, members, warnings, access requests
├── ground-control/   level 3 – mission control: every team; operator and flight surgeon roles
├── common/           shared code (API client, mock server, parameter catalogue, scoring,
│                     i18n, 2D/3D disks, suit, maps, charts, styles, vendored libraries)
├── docs/API.md       requests sent to the server and the JSON formats
└── samples/          sample measurement JSON files (for upload)
```

Each project has its own `index.html` + `config.json` + `js/main.js` and uses `common/` via relative paths.
There is no build step and no external CDN: Three.js, Leaflet and the Moon texture
(`common/vendor/textures/moon_2k.jpg`, from NASA imagery via the MIT-licensed `gravityexp` package) live in
`common/vendor`, so the UI runs offline — only the OpenStreetMap tiles of the Earth map need internet access.

## Running it

The code uses ES modules, so it must be served over HTTP (opening the files directly does not work).
From the `frontend` folder:

```
start_dev_server.bat        (Windows)    →  http://localhost:8080/
./start_dev_server.sh       (Linux/Mac)
```

The script refuses to start if port 8080 is already taken (e.g. another copy of the UI is still running),
so you never end up looking at a different server by mistake. If the page looks outdated, reload with Ctrl+F5.
Any other static web server works too.

In demo mode the login screen lists demo accounts to pick from. When served from the same origin, the three
consoles share one **mock state** (localStorage): a team leader's warning shows up for the crew member, and the
crew member's consent unlocks private data for the team leader.

## Server connection — `config.json`

| key | meaning |
|---|---|
| `mode` | `mock` (built-in demo data), `live` (server only), `auto` (server, falls back to mock if unreachable) |
| `server.baseUrl`, `timeoutMs`, `apiKey`, `withCredentials` | how to reach the server |
| `endpoints` | (optional) override endpoint paths; defaults in `common/js/config.js` |
| `polling` | refresh intervals (seconds) |
| `privacy.showRawValuesToNonPhysicians` | default `false`: non-physicians only see scores/colours |
| `defaultLanguage` | `en, ru, ja, fr, de, it, hu` |

The request/response contract is documented in `docs/API.md`.

## Dashboard

The personal dashboard is a grid of tiles. Tiles can be added with **+**, reordered by dragging, removed with
**✕** and **maximized** with **⤢** (restore with ⤡, Esc, a click on the dimmed background, or a double-click
on the tile header). The layout is saved per user and role.

### Status categories and mission readiness

Every person has five status scores (0–100, green / yellow / red), each shown on its own tile:

| Status | Based on | Weight in readiness |
|---|---|---|
| **Health status** | all physiological parameters | 35 % |
| **Mental health status** | isolation & confinement (days in isolation, weekly confinement questionnaire), mood screening, cognitive test | 20 % |
| **Environmental status** | space radiation (dose rate, mission dose), gravity fields (gravity level, days in reduced gravity), habitat life support (CO₂, O₂, pressure, temperature, humidity, noise) | 20 % |
| **Location status** | age of the newest position fix — OK ≤ 15 min, warning ≤ 60 min | 10 % |
| **Communication status** | time since last contact — OK ≤ 10 min, warning ≤ 60 min; a warning left unacknowledged for > 30 min also lowers it | 15 % |

**Mission readiness** is the weighted mean of the five; a critical category caps it at 45 so a problem cannot be
averaged away. Team and group readiness is the mean of the members' readiness. Member and team cards show the five
statuses as small chips (♥ ◉ ☢ ⌖ 📡), and location/communication problems also appear in the alert lists.

## Requirements coverage

| # | Requirement | Implementation |
|---|---|---|
| 2 | 3-level visualization, drill-down | single-user / team-leader (click a member for details) / ground-control (all → team → individual) |
| 3 | GC physician role, scores for non-physicians, warnings | `physician`: raw value table, ECG, DICOM/PDF, evaluation form; `operator`: scores only; both can send warnings |
| 4 | Multilingual UI | EN, RU, JA, FR, DE, IT, HU — EN/HU/RU complete; JA/FR/DE/IT main UI, other strings fall back to English |
| 5 | Journal upload (name, time, metadata) | journal dialog: name*, time* + time zone, key–value metadata, text, private flag |
| 6 | DataMonitoringCircle | `common/js/components/diskChart.js`: 12 sectors, each parameter on its own scale with red/yellow/green bands |
| 7 | TL 3D disk, layer selection | `disk3d.js` (Three.js): one layer per member + team average; click/dropdown highlights a layer, spacing slider |
| 8 | GC 3D: per team and overall | overview: team-average layers + overall average; team view: members + average |
| 9 | Physiological + environmental parameters | 30 physiological/mental + 10 environmental parameters (radiation, gravity, temperature, humidity, CO₂, O₂, pressure, noise) — `params.js` |
| 10 | Own colour, adjustable | colour picker in the single-user header; suit, disk and cards use it |
| – | Profile picture | click your avatar in the header to upload (cropped to a square, 192 px); shown on cards, 3D disk labels and the round map markers (Earth, station, Moon 2D/3D) |
| 11 | Gamified colour scale | mission readiness 0–100 from five status categories, level/rank/XP/streak, green/yellow/red; detailed data for physicians only |
| 13–14 | Scale-independent, own unit and range | `scoring.js`: piecewise-linear normalisation onto each parameter's own ok/warn range |
| 15 | Measurement points on the suit | `suitView.js` — worst status per point, pulses when critical |
| 16, 18 | Map: Earth / space station / Moon | `mapView.js`: Leaflet + OSM; station schematic with modules; Moon: 2D south-pole view with scroll zoom — zooming out switches to a rotatable 3D globe (`moonGlobe.js`, real NASA-based lunar map with relief shading, named craters and maria), zooming close to the surface returns to 2D |
| 17 | Single and continuous measurements | `mode: single/continuous` per parameter, shown in the UI |
| 19 | Questionnaires, journals | sleep diary (→ sleep time), mood screening (→ score, private by default), isolation & confinement (→ confinement stress) |
| 20 | Camera, data series, DICOM, image, PDF | Files & media tile; camera and ultrasound are demo previews |
| 21 | Simple UI with a “+” button | tiles added with “+”, reordered by dragging, removable, maximizable; saved per user |
| 22 | Upload + private flag | JSON file or manual entry, “Private” checkbox |
| 23 | Time zones | ISO-8601 with offset; source time zone (UTC/ISS, LTC/Moon, IANA); dual time display, clocks in the header |
| 25, 32 | Sending warnings | TL → member; GC → TL or anyone; read acknowledgement; notification for the user |
| 26 | 3 separate projects | `single-user/`, `team-leader/`, `ground-control/` |
| 27, 30, 31 | Server requests, JSON upload, config | `common/js/api.js` + `docs/API.md`; one `config.json` per project |
| 28 | Browser, clean space-themed look | dark deep-space palette, telemetry cyan / nebula violet / re-entry orange |
| 35 | Granting access | TL “Request access” → the crew member grants / denies / revokes on their Privacy tile |

## Sample data

The mock server uses real astronaut names:

- **ISS Expedition 75** (crew aboard in November 2026): Pyotr Dubrov (ISS commander, team leader), Anna Kikina, Anil Menon — Soyuz MS-29; Jessica Watkins, Luke Delaney, Joshua Kutryk, Sergei Teteryatnikov — SpaceX Crew-13
- **Artemis Base Alpha** (fictional lunar base scenario): the Artemis II crew — Reid Wiseman, Victor Glover, Christina Koch, Jeremy Hansen
- **HUNOR Analog Mission** (fictional Earth analog): Tibor Kapu, Gyula Cserényi, Sławosz Uznański-Wiśniewski, Shubhanshu Shukla
- Ground control: fictional characters (Flight Director, Dr. Ilona Varga)
- Default profile pictures: illustrated avatars (`common/assets/avatars/<id>.svg`) in the user's colour with initials and a team-specific helmet; a picture uploaded by the user replaces it
- Demo link problems: Jeremy Hansen's position data is delayed (location warning) and Sławosz Uznański-Wiśniewski's contact is delayed (communication warning)

## Known limitations / next steps

- Access control (private data, roles) **must be enforced by the server**; the client only displays. The mock server simulates it.
- DICOM: only listed with a demo image; a real viewer (e.g. Cornerstone3D) is planned.
- Camera: a real stream URL needs a `<video>`/WebRTC player; currently a demo.
- JA/FR/DE/IT translations are partial; parameter names exist in EN/HU/RU.
- The thresholds in `params.js` need professional medical validation.
- LTC (Coordinated Lunar Time) is currently identical to UTC.
