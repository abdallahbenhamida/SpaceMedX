// =============================================================================
// Parameter catalogue — every physiological / environmental / questionnaire
// parameter with its unit, scale ranges, sector (DataMonitoringCircle) and
// the measurement point on the suit.
//
// Ranges (all in the parameter's own unit — the system is scale independent,
// see scoring.js):
//   axis : [min, max]      visual axis bounds (gray beyond)
//   ok   : [lo, hi]        healthy (green)
//   warn : [lo, hi]        warning (yellow); outside this → critical (red)
// mode   : 'continuous' (wearable stream) | 'single' (lab / periodic check)
// source : 'sensor' | 'questionnaire' | 'journal' | 'lab' | 'environment'
// clinical: true → raw value / detail is physician-only at Ground Control
// disk: false → shown in the Environment panel only (keeps sector XII readable)
// =============================================================================

export const SECTORS = [
  { id: 1,  roman: 'I',    key: 'sector.integumentary' },
  { id: 2,  roman: 'II',   key: 'sector.muscular' },
  { id: 3,  roman: 'III',  key: 'sector.skeletal' },
  { id: 4,  roman: 'IV',   key: 'sector.nervous' },
  { id: 5,  roman: 'V',    key: 'sector.circulatory' },
  { id: 6,  roman: 'VI',   key: 'sector.endocrine' },
  { id: 7,  roman: 'VII',  key: 'sector.respiratory' },
  { id: 8,  roman: 'VIII', key: 'sector.immune' },
  { id: 9,  roman: 'IX',   key: 'sector.urinary' },
  { id: 10, roman: 'X',    key: 'sector.reproductive' },
  { id: 11, roman: 'XI',   key: 'sector.digestive' },
  { id: 12, roman: 'XII',  key: 'sector.external' },
];

// name: { en, hu, ru } — other UI languages fall back to English.
export const PARAMS = [
  // I. Integumentary
  { id: 'skinTemp', sector: 1, name: { en: 'Skin temperature', hu: 'Bőrhőmérséklet', ru: 'Температура кожи' }, unit: '°C', axis: [28, 40], ok: [32, 35.5], warn: [30.5, 37], mode: 'continuous', source: 'sensor', body: 'wristL', clinical: false },
  { id: 'skinConductance', sector: 1, name: { en: 'Skin conductance', hu: 'Bőrvezetés', ru: 'Электропроводность кожи' }, unit: 'µS', axis: [0, 30], ok: [2, 12], warn: [1, 20], mode: 'continuous', source: 'sensor', body: 'wristL', clinical: false },
  // II. Muscular
  { id: 'stepCount', sector: 2, name: { en: 'Step count', hu: 'Lépésszám', ru: 'Шаги' }, unit: 'steps/day', axis: [0, 25000], ok: [6000, 16000], warn: [3000, 20000], mode: 'continuous', source: 'sensor', body: 'waist', clinical: false },
  { id: 'met', sector: 2, name: { en: 'MET', hu: 'MET', ru: 'MET' }, unit: 'MET', axis: [0, 14], ok: [1.2, 8], warn: [1, 11], mode: 'continuous', source: 'sensor', body: 'waist', clinical: false },
  { id: 'gripStrength', sector: 2, name: { en: 'Grip strength', hu: 'Szorítóerő', ru: 'Сила хвата' }, unit: 'kg', axis: [0, 80], ok: [30, 70], warn: [22, 75], mode: 'single', source: 'lab', body: 'handR', clinical: false },
  // III. Skeletal
  { id: 'bodyWeight', sector: 3, name: { en: 'Body weight', hu: 'Testsúly', ru: 'Масса тела' }, unit: 'kg', axis: [40, 130], ok: [60, 90], warn: [52, 100], mode: 'single', source: 'lab', body: 'torso', clinical: false },
  { id: 'boneDensityT', sector: 3, name: { en: 'Bone density (T-score)', hu: 'Csontsűrűség (T-score)', ru: 'Плотность костей (T)' }, unit: 'SD', axis: [-4, 3], ok: [-1, 3], warn: [-2.5, 3], mode: 'single', source: 'lab', body: 'thighL', clinical: true },
  { id: 'coreTemp', sector: 3, name: { en: 'Core temperature', hu: 'Maghőmérséklet', ru: 'Температура ядра' }, unit: '°C', axis: [34, 41], ok: [36.1, 37.5], warn: [35.5, 38.3], mode: 'continuous', source: 'sensor', body: 'head', clinical: false },
  // IV. Nervous
  { id: 'reactionTime', sector: 4, name: { en: 'Reaction time', hu: 'Reakcióidő', ru: 'Время реакции' }, unit: 'ms', axis: [100, 700], ok: [180, 320], warn: [150, 420], mode: 'single', source: 'lab', body: 'head', clinical: false },
  { id: 'cognitiveScore', sector: 4, name: { en: 'Cognitive test', hu: 'Kognitív teszt', ru: 'Когнитивный тест' }, unit: 'pts', axis: [0, 100], ok: [70, 100], warn: [55, 100], mode: 'single', source: 'questionnaire', body: 'head', clinical: false },
  { id: 'moodScore', sector: 4, name: { en: 'Mood screening', hu: 'Hangulat-szűrő', ru: 'Скрининг настроения' }, unit: 'pts', axis: [0, 15], ok: [0, 4], warn: [0, 9], mode: 'single', source: 'questionnaire', body: 'head', clinical: true },
  // V. Circulatory
  { id: 'heartRate', sector: 5, name: { en: 'Heart rate', hu: 'Pulzus', ru: 'ЧСС' }, unit: 'bpm', axis: [30, 200], ok: [55, 100], warn: [45, 130], mode: 'continuous', source: 'sensor', body: 'chest', clinical: false },
  { id: 'systolic', sector: 5, name: { en: 'Systolic BP', hu: 'Szisztolés vérnyomás', ru: 'Систолическое АД' }, unit: 'mmHg', axis: [70, 200], ok: [100, 130], warn: [90, 150], mode: 'continuous', source: 'sensor', body: 'armL', clinical: false },
  { id: 'diastolic', sector: 5, name: { en: 'Diastolic BP', hu: 'Diasztolés vérnyomás', ru: 'Диастолическое АД' }, unit: 'mmHg', axis: [40, 130], ok: [60, 85], warn: [55, 95], mode: 'continuous', source: 'sensor', body: 'armL', clinical: false },
  { id: 'hrv', sector: 5, name: { en: 'HRV (RMSSD)', hu: 'HRV (RMSSD)', ru: 'ВСР (RMSSD)' }, unit: 'ms', axis: [0, 150], ok: [30, 120], warn: [18, 140], mode: 'continuous', source: 'sensor', body: 'chest', clinical: true },
  // VI. Endocrine
  { id: 'bloodGlucose', sector: 6, name: { en: 'Blood glucose', hu: 'Vércukor', ru: 'Глюкоза крови' }, unit: 'mmol/L', axis: [2, 16], ok: [3.9, 7.8], warn: [3.3, 10], mode: 'single', source: 'lab', body: 'handL', clinical: false },
  { id: 'cortisol', sector: 6, name: { en: 'Salivary cortisol', hu: 'Nyál-kortizol', ru: 'Кортизол слюны' }, unit: 'nmol/L', axis: [0, 40], ok: [3, 20], warn: [1.5, 28], mode: 'single', source: 'lab', body: 'head', clinical: true },
  // VII. Respiratory
  { id: 'respRate', sector: 7, name: { en: 'Breathing frequency', hu: 'Légzésszám', ru: 'Частота дыхания' }, unit: '1/min', axis: [4, 40], ok: [12, 20], warn: [9, 26], mode: 'continuous', source: 'sensor', body: 'chest', clinical: false },
  { id: 'spo2', sector: 7, name: { en: 'SpO₂', hu: 'SpO₂', ru: 'SpO₂' }, unit: '%', axis: [80, 100], ok: [95, 100], warn: [91, 100], mode: 'continuous', source: 'sensor', body: 'handR', clinical: false },
  { id: 'fev1', sector: 7, name: { en: 'FEV1', hu: 'FEV1', ru: 'ОФВ1' }, unit: 'L', axis: [1, 6], ok: [3, 5.5], warn: [2.4, 6], mode: 'single', source: 'lab', body: 'chest', clinical: true },
  { id: 'peakFlow', sector: 7, name: { en: 'Peak flow', hu: 'Csúcsáramlás', ru: 'Пиковый поток' }, unit: 'L/min', axis: [150, 800], ok: [400, 700], warn: [320, 750], mode: 'single', source: 'lab', body: 'chest', clinical: false },
  // VIII. Lymphatic / immune
  { id: 'wbc', sector: 8, name: { en: 'White blood cells', hu: 'Fehérvérsejtszám', ru: 'Лейкоциты' }, unit: '10⁹/L', axis: [0, 20], ok: [4, 10], warn: [3, 12.5], mode: 'single', source: 'lab', body: 'armR', clinical: true },
  { id: 'crp', sector: 8, name: { en: 'CRP', hu: 'CRP', ru: 'СРБ' }, unit: 'mg/L', axis: [0, 50], ok: [0, 5], warn: [0, 15], mode: 'single', source: 'lab', body: 'armR', clinical: true },
  // IX. Urinary / excretory
  { id: 'urineSG', sector: 9, name: { en: 'Urine specific gravity', hu: 'Vizelet fajsúly', ru: 'Удельный вес мочи' }, unit: 'g/mL', axis: [1.000, 1.040], ok: [1.005, 1.025], warn: [1.003, 1.030], mode: 'single', source: 'lab', body: 'waist', clinical: true },
  { id: 'fluidIntake', sector: 9, name: { en: 'Fluid intake', hu: 'Folyadékbevitel', ru: 'Потребление жидкости' }, unit: 'L/day', axis: [0, 5], ok: [2, 3.5], warn: [1.5, 4.2], mode: 'single', source: 'journal', body: 'torso', clinical: false },
  // X. Reproductive — intentionally empty in v1 (sector still drawn)
  // XI. Digestive
  { id: 'calorieIntake', sector: 11, name: { en: 'Calorie intake', hu: 'Kalóriabevitel', ru: 'Калорийность' }, unit: 'kcal/day', axis: [800, 4500], ok: [2200, 3200], warn: [1800, 3700], mode: 'single', source: 'journal', body: 'torso', clinical: false },
  // XII. External & derived (incl. environment)
  { id: 'sleepTime', sector: 12, name: { en: 'Sleeping time', hu: 'Alvásidő', ru: 'Время сна' }, unit: 'h', axis: [0, 12], ok: [6.5, 9], warn: [5.5, 10], mode: 'single', source: 'questionnaire', body: 'head', clinical: false },
  { id: 'sittingTime', sector: 12, name: { en: 'Sitting time', hu: 'Ülési idő', ru: 'Время сидя' }, unit: 'h/day', axis: [0, 16], ok: [0, 8], warn: [0, 11], mode: 'continuous', source: 'sensor', body: 'waist', clinical: false },
  { id: 'radDoseRate', sector: 12, name: { en: 'Radiation dose rate', hu: 'Sugárzási dózisteljesítmény', ru: 'Мощность дозы' }, unit: 'µSv/h', axis: [0, 120], ok: [0, 30], warn: [0, 60], mode: 'continuous', source: 'environment', body: 'shoulderL', clinical: false, env: true },
  { id: 'radDoseMission', sector: 12, name: { en: 'Mission dose', hu: 'Kumulált küldetésdózis', ru: 'Накопленная доза' }, unit: 'mSv', axis: [0, 600], ok: [0, 150], warn: [0, 400], mode: 'continuous', source: 'environment', body: 'shoulderL', clinical: false, env: true },
  { id: 'cabinTemp', sector: 12, name: { en: 'Ambient temperature', hu: 'Környezeti hőmérséklet', ru: 'Температура среды' }, unit: '°C', axis: [10, 35], ok: [18.5, 26.5], warn: [16, 29], mode: 'continuous', source: 'environment', body: null, clinical: false, env: true },
  { id: 'humidity', sector: 12, disk: false, name: { en: 'Relative humidity', hu: 'Páratartalom', ru: 'Влажность' }, unit: '%', axis: [0, 100], ok: [30, 65], warn: [25, 75], mode: 'continuous', source: 'environment', body: null, clinical: false, env: true },
  { id: 'co2', sector: 12, name: { en: 'CO₂ level', hu: 'CO₂-szint', ru: 'Уровень CO₂' }, unit: 'ppm', axis: [300, 8000], ok: [300, 2600], warn: [300, 5000], mode: 'continuous', source: 'environment', body: null, clinical: false, env: true },
  { id: 'ppO2', sector: 12, disk: false, name: { en: 'O₂ partial pressure', hu: 'O₂ parciális nyomás', ru: 'Парц. давление O₂' }, unit: 'kPa', axis: [14, 30], ok: [19.5, 23.1], warn: [17.5, 25], mode: 'continuous', source: 'environment', body: null, clinical: false, env: true },
  { id: 'cabinPressure', sector: 12, disk: false, name: { en: 'Ambient pressure', hu: 'Környezeti nyomás', ru: 'Давление' }, unit: 'kPa', axis: [60, 110], ok: [97, 103], warn: [90, 105], mode: 'continuous', source: 'environment', body: null, clinical: false, env: true },
  { id: 'noise', sector: 12, disk: false, name: { en: 'Noise level', hu: 'Zajszint', ru: 'Уровень шума' }, unit: 'dBA', axis: [20, 100], ok: [20, 60], warn: [20, 72], mode: 'continuous', source: 'environment', body: 'head', clinical: false, env: true },
];

export const PARAM_BY_ID = Object.fromEntries(PARAMS.map(p => [p.id, p]));

export function paramName(p, lang) {
  if (typeof p === 'string') p = PARAM_BY_ID[p];
  if (!p) return '?';
  return p.name[lang] || p.name.en;
}

export function paramsInSector(sectorId) {
  return PARAMS.filter(p => p.sector === sectorId);
}

// Suit measurement points (normalised 0..1 coordinates on the front silhouette
// drawn by suitView.js — viewBox 200 x 420).
export const BODY_POINTS = {
  head:      { x: 100, y: 38,  key: 'body.head' },
  chest:     { x: 100, y: 118, key: 'body.chest' },
  torso:     { x: 100, y: 165, key: 'body.torso' },
  waist:     { x: 100, y: 205, key: 'body.waist' },
  shoulderL: { x: 140, y: 92,  key: 'body.shoulderL' },
  armL:      { x: 152, y: 140, key: 'body.armL' },
  armR:      { x: 48,  y: 140, key: 'body.armR' },
  wristL:    { x: 160, y: 205, key: 'body.wristL' },
  handL:     { x: 163, y: 232, key: 'body.handL' },
  handR:     { x: 37,  y: 232, key: 'body.handR' },
  thighL:    { x: 118, y: 270, key: 'body.thighL' },
};

/** Parameters drawn on the DataMonitoringCircle / 3D disks. */
export const DISK_PARAMS = PARAMS.filter(p => p.disk !== false);
