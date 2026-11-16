import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ml/iss_env_model.dart';

/// Replays 48 hours of ISS cabin data that NASA recorded (OSDR Environmental Data App) and lets the
/// ISS model colour it. It is a replay of a recording, not a live feed: one 30-minute sample every
/// [tick], then it starts again.
class IssEnvPlayer extends ChangeNotifier {
  IssEnvPlayer({this.tick = const Duration(seconds: 4)});

  static final IssEnvPlayer instance = IssEnvPlayer();

  final Duration tick;

  /// The newest assessment of CO2, temperature, humidity and radiation (empty until loaded).
  List<IssAssessment> assessments = const [];

  /// Mission the recording comes from (for example "RR-3").
  String mission = '';

  /// When the shown sample was recorded (UTC).
  DateTime? sampleTime;

  List<double> _co2 = const [];
  List<double> _temp = const [];
  List<double> _rh = const [];
  final Map<String, double> _rad = {};
  int _stepMinutes = 30;
  DateTime _start = DateTime.utc(2000);
  int _i = 0;
  final IssEnvMonitor _monitor = IssEnvMonitor();
  Timer? _timer;
  int _users = 0;
  bool _loading = false;

  bool get ready => _co2.isNotEmpty;

  /// A screen that shows the strip calls this when it appears and [detach] when it goes.
  void attach() {
    _users++;
    if (!ready) {
      load();
    } else {
      _startTimer();
    }
  }

  void detach() {
    if (_users > 0) _users--;
    if (_users == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> load([AssetBundle? bundle]) async {
    if (ready || _loading) return;
    _loading = true;
    try {
      final text = await (bundle ?? rootBundle).loadString('assets/data/iss_env_sample.json');
      loadFromJson(text);
    } catch (e) {
      debugPrint('ISS sample not loaded: $e');
    }
    _loading = false;
  }

  /// The JSON of `assets/data/iss_env_sample.json`.
  void loadFromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    List<double> nums(String k) => [for (final x in j[k] as List<dynamic>) (x as num).toDouble()];
    _co2 = nums('co2');
    _temp = nums('temperature');
    _rh = nums('humidity');
    _stepMinutes = (j['stepMinutes'] as num?)?.toInt() ?? 30;
    mission = '${j['mission'] ?? ''}';
    _start = DateTime.parse('${j['start']}').toUtc();
    _rad.clear();
    for (final r in (j['radiation'] as List<dynamic>? ?? const [])) {
      final m = r as Map<String, dynamic>;
      _rad['${m['date']}'] = (m['total'] as num).toDouble();
    }
    _rewind();
    notifyListeners();
    if (_users > 0) _startTimer();
  }

  void _startTimer() => _timer ??= Timer.periodic(tick, (_) => step());

  /// Gives the model its 4 hours of history, then shows the next sample.
  void _rewind() {
    _monitor.reset();
    _i = 0;
    while (_i < IssEnvModel.historySteps && _i < _co2.length - 1) {
      _feed(_i);
      _i++;
    }
    _feed(_i);
  }

  void _feed(int i) {
    final t = _start.add(Duration(minutes: i * _stepMinutes));
    sampleTime = t;
    final day = t.toIso8601String().substring(0, 10);
    assessments = _monitor.addSample(co2: _co2[i], temperature: _temp[i], humidity: _rh[i], radiation: _rad[day]);
  }

  /// Moves on by one sample (called by the timer).
  void step() {
    if (!ready) return;
    _i++;
    if (_i >= _co2.length) {
      _rewind();
    } else {
      _feed(_i);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
