import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../ml/vitals_model.dart';
import 'analysis.dart';
import 'local_store.dart';
import 'settings.dart';

/// The newest value of a parameter.
class Reading {
  const Reading(this.time, this.value, this.level, this.label);
  final DateTime time;
  final double value;
  final Level level;
  final String label;
}

/// A warning the astronaut should see.
class HealthAlert {
  const HealthAlert(this.time, this.paramId, this.level, this.title, this.text,
      {this.value = '', this.label = ''});
  final DateTime time;
  final String paramId; // 'hr', 'bp', 'glu'
  final Level level;
  final String title; // English key
  final String text; // English text (for the log)
  final String value; // "128/82 mmHg"
  final String label; // English key of the range name, for example "Grade 1 hypertension"

  /// The alert in the language of the app.
  String get titleText => tr(title);
  String get detailText => value.isEmpty ? (label.isEmpty ? text : tr(label)) : '$value: ${tr(label)}';
}

/// Short event log shown under Settings > Diagnostics.
class AppLog extends ChangeNotifier {
  AppLog._();
  static final AppLog instance = AppLog._();
  final List<String> lines = [];

  static void add(String source, String text) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $source: $text';
    debugPrint(line);
    instance.lines.add(line);
    if (instance.lines.length > 300) instance.lines.removeRange(0, instance.lines.length - 300);
    instance.notifyListeners();
  }
}

/// Every measurement of every source goes through here: it is kept on the
/// phone (for the charts), judged against the ranges, and may raise an alert.
class Recorder extends ChangeNotifier {
  Recorder({LocalStore? store, AppSettings? settings, this.haptics = true})
      : store = store ?? MemoryStore(),
        _settings = settings ?? AppSettings.instance;

  static final Recorder instance = Recorder();

  LocalStore store;
  final AppSettings _settings;
  final bool haptics;

  /// Newest reading per parameter id ('hr', 'sys', 'dia', 'glu').
  final Map<String, Reading> latest = {};
  final List<HealthAlert> alerts = [];

  /// How many consecutive abnormal heart rate readings raise an alert (so a
  /// single bad sample does not).
  static const int sustainedSamples = 5;
  static const Duration alertRepeat = Duration(minutes: 5);

  final Map<String, int> _streak = {};
  final Map<String, (Level, DateTime)> _lastAlert = {};

  /// Every data type that can be charted: the ones with ranges, and (as they
  /// appear) the ones a source registers, for example the sensors of a new source.
  /// Skin temperature: charted, but the app has no normal range for it; the vitals model watches it.
  static const ParamDef tempDef = ParamDef.plain(id: 'temp', name: 'Temperature', unit: '°C', decimals: 1);

  final Map<String, ParamDef> defs = {for (final p in Ranges.all) p.id: p, tempDef.id: tempDef};

  // the small models (lib/ml): heart rate / temperature changes
  final Map<String, _MinuteFeed> _minutes = {};

  void registerParam(ParamDef def) {
    if (defs.containsKey(def.id)) return;
    defs[def.id] = def;
    store.saveParamDef(def.id, def.name, def.unit, def.decimals).catchError((Object _) {});
  }

  /// After a restart: bring back the names of the data types seen before.
  Future<void> loadDefs() async {
    try {
      for (final d in await store.paramDefs()) {
        defs.putIfAbsent(
          d.id,
          () => ParamDef.plain(id: d.id, name: d.name, unit: d.unit, decimals: d.decimals),
        );
      }
    } catch (_) {}
  }

  Future<void> record(String paramId, double value, {DateTime? time, String source = ''}) async {
    final def = defs[paramId];
    if (def == null || value.isNaN || value.isInfinite) return;
    final t = time ?? DateTime.now();
    await _save(paramId, t, value, source);
    final band = def.bandOf(value);
    final level = band?.level ?? Level.unknown;
    final old = latest[paramId];
    if (old == null || !t.isBefore(old.time)) {
      latest[paramId] = Reading(t, value, level, band?.label ?? '');
    }
    if (paramId == 'hr') {
      _feedVitals('hr', VitalSignal.heartRate, value, t, 'bpm', 'Unusual heart rate change');
      _judge('hr', level, 'Heart rate', '${def.format(value)} ${def.unit}', band?.label ?? '', t,
          needed: sustainedSamples);
    } else if (paramId == 'temp') {
      _feedVitals('temp', VitalSignal.temperature, value, t, '°C', 'Unusual temperature change');
    } else if (paramId == 'glu') {
      _judge('glu', level, 'Blood glucose', '${def.format(value)} ${def.unit}', band?.label ?? '', t);
    }
    notifyListeners();
  }

  /// One blood pressure measurement (both numbers are judged together).
  Future<void> recordBloodPressure(double sys, double dia, {DateTime? time, String source = ''}) async {
    final t = time ?? DateTime.now();
    await _save('sys', t, sys, source);
    await _save('dia', t, dia, source);
    final r = Ranges.bloodPressure(sys, dia);
    latest['sys'] = Reading(t, sys, Ranges.systolic.levelOf(sys), Ranges.systolic.bandOf(sys)?.label ?? '');
    latest['dia'] = Reading(t, dia, Ranges.diastolic.levelOf(dia), Ranges.diastolic.bandOf(dia)?.label ?? '');
    _judge('bp', r.level, 'Blood pressure', '${sys.round()}/${dia.round()} mmHg', r.label, t);
    notifyListeners();
  }

  /// One value per minute (the median of that minute) goes to the heart rate / temperature monitor.
  void _feedVitals(String key, VitalSignal signal, double v, DateTime t, String unit, String title) {
    final m = _minutes.putIfAbsent(key, () => _MinuteFeed(VitalsMonitor(signal)));
    final minute = t.millisecondsSinceEpoch ~/ 60000;
    if (m.minute != null && minute < m.minute!) return; // an old value: ignore
    if (m.minute != null && minute != m.minute) {
      final closed = m.minute!;
      final med = VitalsModel.median(m.values);
      m.values.clear();
      if (m.lastClosed != null && closed - m.lastClosed! > 2) m.monitor.reset(); // a gap: start again
      m.lastClosed = closed;
      final d = m.monitor.addMinute(med);
      if (d != null && d.alert) {
        final shown = key == 'hr' ? d.value.round().toString() : d.value.toStringAsFixed(1);
        _modelAlert('v_$key', Level.attention, title, '$shown $unit', 'Changed faster than expected', t);
      }
    }
    m.minute = minute;
    m.values.add(v);
  }

  /// An alert from one of the models. The same alert is not repeated within [alertRepeat].
  void _modelAlert(String key, Level level, String title, String value, String label, DateTime t) {
    final last = _lastAlert[key];
    if (last != null && t.difference(last.$2) < alertRepeat && level.rank <= last.$1.rank) return;
    _lastAlert[key] = (level, t);
    _emit(key, level, title, value, label, t);
    notifyListeners();
  }

  Future<void> _save(String param, DateTime t, double v, String source) async {
    try {
      await store.addObservation(param, t, v, source);
    } catch (e) {
      AppLog.add('storage', 'could not save a value: $e');
    }
  }

  void _judge(String key, Level level, String title, String value, String label, DateTime t,
      {int needed = 1}) {
    if (!level.isAlert) {
      _streak[key] = 0;
      _lastAlert.remove(key);
      return;
    }
    final n = (_streak[key] ?? 0) + 1;
    _streak[key] = n;
    if (n < needed) return;
    final last = _lastAlert[key];
    final worse = last == null || level.rank > last.$1.rank;
    final due = last == null || t.difference(last.$2) >= alertRepeat;
    if (!worse && !due) return;
    _lastAlert[key] = (level, t);
    _emit(key, level, title, value, label, t);
  }

  void _emit(String key, Level level, String title, String value, String label, DateTime t) {
    final text = value.isEmpty ? label : '$value: $label';
    final a = HealthAlert(t, key, level, title, text, value: value, label: label);
    alerts.insert(0, a);
    if (alerts.length > 50) alerts.removeLast();
    AppLog.add('alert', '$title: $text');
    if (level.isAlert && haptics && _settings.alertsOn && _settings.vibrate) { // a model "attention" note does not vibrate
      HapticFeedback.heavyImpact();
    }
  }

  void clearAlerts() {
    alerts.clear();
    notifyListeners();
  }

  /// Forget the readings and alerts shown (not the stored history).
  void resetLive() {
    latest.clear();
    alerts.clear();
    _streak.clear();
    _lastAlert.clear();
    for (final m in _minutes.values) {
      m.monitor.reset();
      m.values.clear();
      m.minute = null;
      m.lastClosed = null;
    }
    notifyListeners();
  }

  /// Keep the history only for [AppSettings.historyDays].
  Future<void> purgeOld() async {
    try {
      await store.purgeOlderThan(DateTime.now().subtract(Duration(days: _settings.historyDays)));
    } catch (_) {}
  }
}

/// The values of the minute that is running, for the heart rate / temperature monitor.
class _MinuteFeed {
  _MinuteFeed(this.monitor);
  final VitalsMonitor monitor;
  final List<double> values = <double>[];
  int? minute;
  int? lastClosed;
}
