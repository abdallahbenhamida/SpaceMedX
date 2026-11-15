# Crew Health Monitor — Visualization (v0.1)

Böngészős megjelenítő három szinttel, a `Visualization_Requirements_VM01.xlsx` alapján.

```
Development/
├── single-user/      1. szint – a személyzeti tag saját, egyszerűsített felülete
├── team-leader/      2. szint – csapatvezető: 3D diszkek, tagok, figyelmeztetés, hozzáférés-kérés
├── ground-control/   3. szint – földi irányítás: minden csapat; operátor és orvos szerep
├── common/           közös kód (API-kliens, mock szerver, paraméterkatalógus, pontozás,
│                     i18n, diszk 2D/3D, ruha, térkép, grafikonok, stílus, vendor libek)
├── docs/API.md       a PHP szerver felé küldött lekérések és a JSON formátum
└── samples/          minta mérés-JSON-ok (feltöltéshez)
```

Mindhárom projekt külön `index.html` + `config.json` + `js/main.js`; a `common/` mappát relatív úton használják.
Nincs build lépés, nincs külső CDN: a Three.js, a Leaflet és a Hold-textúra (`common/vendor/textures/moon_2k.jpg`, NASA-felvételekből, a `gravityexp` MIT-csomagból) a `common/vendor` alatt van (offline is fut — csak a földi térkép OSM-csempéihez kell internet).

## Indítás

ES modulok miatt HTTP-ről kell kiszolgálni (fájlból megnyitva nem fut). A `Development` mappából:

```
start_dev_server.bat        (Windows)   →  http://localhost:8080/
./start_dev_server.sh       (Linux/Mac)
```

Vagy bármely webszerverről (pl. a PHP szerver mellé másolva). Demó módban a belépőképernyőn demó fiókok közül lehet választani.
Ugyanarról az originről futtatva a három felület **közös mock-állapotot** használ (localStorage), így pl. a csapatvezető figyelmeztetése megjelenik a felhasználónál, a felhasználó engedélye feloldja a csapatvezetőnél a privát adatot.

## Szerverkapcsolat — `config.json`

| kulcs | jelentés |
|---|---|
| `mode` | `mock` (demó adat), `live` (csak PHP szerver), `auto` (szerver, ha elérhetetlen → mock) |
| `server.baseUrl`, `timeoutMs`, `apiKey`, `withCredentials` | PHP szerver elérése |
| `endpoints` | (opcionális) végpont-útvonalak felülírása, alapértékek: `common/js/config.js` |
| `polling` | frissítési idők (másodperc) |
| `privacy.showRawValuesToNonPhysicians` | alapból `false`: nem orvos csak pontszámot/színt lát |
| `defaultLanguage` | `en, ru, ja, fr, de, it, hu` |

## Követelmények megfeleltetése

| # | Követelmény | Megvalósítás v0.1 |
|---|---|---|
| 2 | 3 szintű vizualizáció, lefúrás | single-user / team-leader (tagra kattintva adatlap) / ground-control (összes → csapat → egyén) |
| 3 | GC orvos szerep, nem orvosnak pontozott érték, figyelmeztetés | `physician`: nyers értéktábla, EKG, DICOM/PDF, értékelés-űrlap; `operator`: csak pontszám; mindkettő küld figyelmeztetést |
| 4 | Többnyelvű UI | EN, RU, JA, FR, DE, IT, HU — EN/HU/RU teljes; JA/FR/DE/IT fő felület, a többi szöveg angolra esik vissza |
| 5 | Naplófeltöltés (név, idő, metaadat) | Napló dialógus: név*, idő* + időzóna, kulcs–érték metaadat, szöveg, privát |
| 6 | DataMonitoringCircle | `common/js/components/diskChart.js`: 12 szektor, paraméterenként saját skála piros/sárga/zöld sávokkal |
| 7 | TL 3D diszk, rétegválasztás | `disk3d.js` (Three.js): tagonként egy réteg + csapatátlag; kattintás/legördülő kiemeli a réteget, távolság csúszka |
| 8 | GC 3D: csapatonként és összesítve | Áttekintés: csapatátlag-rétegek + teljes átlag; csapat nézet: tagok + átlag |
| 9 | Élettani + környezeti paraméterek | 28 élettani + 8 környezeti (sugárzás, hőm., páratartalom, CO₂, O₂, nyomás, zaj) — `params.js` |
| 10 | Saját szín, állítható | színválasztó a single-user fejlécében, ruha/diszk/kártyák ezt használják |
| – | Profilkép | a fejlécben a saját avatarra kattintva tölthető fel (négyzetre vágva, 192 px); megjelenik a kártyákon, a 3D diszk címkéin és a térképek kör alakú jelölőiben (Föld, állomás, Hold 2D/3D) |
| 11 | Gamifikált színskála | Bevetési készültség 0–100, szint/rang/XP/sorozat, zöld/sárga/piros; részletes adat csak orvosnak |
| 13–14 | Skálafüggetlen, saját mértékegység és tartomány | `scoring.js`: szakaszonként lineáris normalizálás a saját ok/warn tartományra |
| 15 | Mérési pontok a ruhán | `suitView.js` — pontonként a legrosszabb státusz, kritikusnál pulzál |
| 16, 18 | Térkép: Föld / űrállomás / Hold | `mapView.js`: Leaflet+OSM; állomás-séma modulokkal; Hold: 2D déli-pólus nézet görgős nagyítással — kicsinyítve forgatható 3D gömbre vált (`moonGlobe.js`, valódi NASA-alapú holdtérkép domborzati árnyalással, nevezetes kráterek és mare-k feliratozva), a felszínhez közel nagyítva vissza 2D-re |
| 17 | Egyszeri és folytonos mérés | `mode: single/continuous` paraméterenként, megjelenítve |
| 19 | Kérdőívek, naplók | alvásnapló (→ alvásidő), hangulat-szűrő (→ pontszám, alapból privát) |
| 20 | Kamera, adatsor, DICOM, kép, PDF | Fájlok és média csempe; v0.1-ben kamera és ultrahang demó-előnézet |
| 21 | Egyszerű UI „+” gombbal | csempék „+”-szal adhatók hozzá, húzással rendezhetők, eltávolíthatók; felhasználónként mentve |
| 22 | Feltöltés + privát jelölés | JSON-fájl vagy kézi bevitel, „Privát” jelölő |
| 23 | Időzónák | ISO-8601 offsettel; forrás-időzóna (UTC/ISS, LTC/Hold, IANA); kettős időkijelzés, órák a fejlécben |
| 25, 32 | Figyelmeztetés küldése | TL → tag; GC → TL vagy bárki; olvasási nyugtázás; értesítés a felhasználónál |
| 26 | 3 külön projekt | `single-user/`, `team-leader/`, `ground-control/` |
| 27, 30, 31 | PHP lekérések, JSON feltöltés, config | `common/js/api.js` + `docs/API.md`; `config.json` projektenként |
| 28 | Böngésző, letisztult űr-színvilág | sötét mélyűr paletta, telemetria-cián / köd-ibolya / visszatérés-narancs |
| 35 | Hozzáférés engedélyezése | TL „Hozzáférés kérése” → felhasználó a saját Adatvédelem csempéjén engedélyez / elutasít / visszavon |

## Mintaadatok

A mock szerver valódi űrhajósneveket használ:

- **ISS Expedition 75** (a 2026. novemberi fedélzeti személyzet): Pyotr Dubrov (ISS-parancsnok, csapatvezető), Anna Kikina, Anil Menon — Soyuz MS-29; Jessica Watkins, Luke Delaney, Joshua Kutryk, Sergei Teteryatnikov — SpaceX Crew-13
- **Artemis Base Alpha** (fiktív holdbázis-forgatókönyv): az Artemis II legénysége — Reid Wiseman, Victor Glover, Christina Koch, Jeremy Hansen
- **HUNOR Analog Mission** (fiktív földi analóg): Kapu Tibor, Cserényi Gyula, Sławosz Uznański-Wiśniewski, Shubhanshu Shukla
- Földi irányítás: fiktív szereplők (Flight Director, Dr. Ilona Varga)
- Alapértelmezett profilképek: rajzolt avatarok (`common/assets/avatars/<id>.svg`) a felhasználó színében, monogrammal, csapatonként eltérő sisakkal; a felhasználó által feltöltött kép felülírja

## Ismert korlátok / következő lépések

- A jogosultság-ellenőrzést (privát adat, szerepek) **a PHP szervernek kell kikényszerítenie**; a kliens csak megjelenít. A mock ezt szimulálja.
- DICOM: v0.1 csak listáz és demó-képet mutat; valódi megjelenítő (pl. Cornerstone3D) a következő verzióban.
- Kamera: valódi stream-URL esetén `<video>`/WebRTC lejátszó kell; most demó.
- JA/FR/DE/IT fordítás részleges; paraméternevek EN/HU/RU.
- A határértékek (`params.js`) szakmai, orvosi validálásra szorulnak.
- LTC (Coordinated Lunar Time) jelenleg UTC-vel azonos.
