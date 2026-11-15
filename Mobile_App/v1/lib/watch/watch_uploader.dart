import 'dart:async';

import '../core/server_client.dart';
import '../core/settings.dart';
import 'watch_protocol.dart';

/// Collects the samples of the parameters the user switched on for upload and
/// posts them to the server in batches (every [interval], or as soon
/// as [maxSamples] are waiting).
class WatchUploader {
  WatchUploader({
    Duration? interval,
    this.maxSamples = 250,
    Future<bool> Function(String type, List<Map<String, Object?>> records)? post,
  })  : interval = interval ?? Duration(seconds: AppSettings.instance.uploadSeconds),
        _post = post ?? ServerClient.instance.post;

  final Duration interval;
  final int maxSamples;
  final Future<bool> Function(String type, List<Map<String, Object?>> records)
      _post;

  /// Server record type per watch parameter.
  static const Map<String, String> serverTypes = {
    'hr': 'pulsebelt',
    'shr': 'pulsebelt',
    'ibi': 'ibi',
    'acc': 'accelerometer',
    'sacc': 'accelerometer',
    'gyr': 'gyroscope',
    'mag': 'magnetometer',
    'steps': 'steps',
    'pres': 'airpressure',
    'light': 'light',
    'off': 'bodypresence',
    'ppg': 'ppg',
    'ecg': 'ecg',
    'spo2': 'spo2',
    'skint': 'skintemperature',
    'bia': 'bodycomposition',
    'eda': 'eda',
  };

  /// Names suggested by the watch for ids not in [serverTypes] (agreed in the "deal").
  final Map<String, String> negotiated = {};

  /// Server record types known to be accepted by the server (the
  /// heart rate "pulsebelt" format was given by the server owner). A watch
  /// sensor is only offered in the app when its type is in this set - add a type
  /// here once the server side is verified.
  static final Set<String> confirmedTypes = {'pulsebelt'};

  bool isConfirmed(String id) => confirmedTypes.contains(typeFor(id));

  String typeFor(String id) => serverTypes[id] ?? negotiated[id] ?? id;

  /// Value names of one uploaded record (what the server receives).
  static List<String> fieldsFor(WatchParam p) => (p.id == 'hr' || p.id == 'shr')
      ? const ['timestamp', 'pulse', 'rr', 'remark']
      : ['timestamp', ...p.fields];

  final Set<String> _enabled = {};
  final Map<String, List<Map<String, Object?>>> _buffers = {};
  Timer? _timer;
  bool _flushing = false;

  /// Optional log sink (shown on the watch page).
  void Function(String level, String text)? onLog;

  int sent = 0;
  int failed = 0;

  Set<String> get enabled => Set.unmodifiable(_enabled);

  void setEnabled(Iterable<String> ids) {
    _enabled
      ..clear()
      ..addAll(ids);
    _buffers.removeWhere((k, _) => !_enabled.contains(k));
    if (_enabled.isEmpty) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(interval, (_) => flush());
    }
  }

  void add(WatchParam param, WatchFrame frame) {
    if (!_enabled.contains(param.id)) return;
    final list = _buffers.putIfAbsent(param.id, () => []);
    for (final s in frame.samples) {
      if (param.id == 'hr' || param.id == 'shr') {
        // Server "pulsebelt" record: {timestamp, pulse:"80", rr:"", remark:""}
        final bpm = s.values.isEmpty ? null : s.values[0];
        if (bpm == null || bpm <= 0) continue;
        list.add({
          'timestamp': s.timeMs,
          'pulse': bpm.round().toString(),
          'rr': '',
          'remark': '',
        });
        continue;
      }
      final rec = <String, Object?>{'timestamp': s.timeMs};
      for (var i = 0; i < param.fields.length && i < s.values.length; i++) {
        rec[param.fields[i]] = s.values[i];
      }
      list.add(rec);
    }
    // fast signals (ECG 500 Hz) go out in bigger batches
    if (list.length >= (param.rateHz >= 100 ? maxSamples * 4 : maxSamples)) flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (final id in _buffers.keys.toList()) {
        final batch = _buffers[id]!;
        if (batch.isEmpty) continue;
        final take = List<Map<String, Object?>>.of(batch);
        batch.clear();
        final type = typeFor(id);
        final ok = await _post(type, take);
        onLog?.call(ok ? 'upload' : 'warn',
            '${ok ? 'sent' : 'FAILED to send'} ${take.length} $type sample(s)');
        if (ok) {
          sent += take.length;
        } else {
          failed += take.length;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await flush();
  }
}
