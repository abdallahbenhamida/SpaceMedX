import 'dart:async';

import 'server_client.dart';
import 'settings.dart';

/// One upload: server record type, the records and the time span.
class Upload {
  const Upload(this.type, this.records, {this.from, this.to, this.count});
  final String type;
  final List<Map<String, Object?>> records;
  final int? from;
  final int? to;
  final int? count;
}

/// Converts the records of the Bluetooth devices (as reported by the e77hal
/// plugin) into the records the server expects. Same record types, names and
/// values as the earlier app (`assets/js/index.js` of the released app).
class DeviceRecords {
  DeviceRecords._();

  static final RegExp _slashDate =
      RegExp(r'(\d{4})\/(\d+)\/(\d+) (\d+):(\d+):(\d+)');
  static final RegExp _dotDate = RegExp(r'(\d{4})\.(\d+)\.(\d+)\. (\d+):(\d+)');

  /// "2026/11/13 9:05:00" (device clock = phone's local time) -> epoch ms.
  static int? _localTime(Object? text, RegExp re) {
    if (text is! String) return null;
    final m = re.firstMatch(text);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      m.groupCount >= 6 && m.group(6) != null ? int.parse(m.group(6)!) : 0,
    ).millisecondsSinceEpoch;
  }

  static void _copy(Map<String, Object?> to, String toKey, Map<String, Object?> from, String fromKey) {
    if (from.containsKey(fromKey)) to[toKey] = from[fromKey];
  }

  /// Beurer BM85 (EID_102): type `bloodpressure`.
  static Upload? beurer(Map<String, Object?> r, {String deviceId = 'EID_102'}) {
    final ts = _localTime(r['MeasurementDateTime'], _slashDate);
    if (ts == null) return null;
    final bp = <String, Object?>{};
    _copy(bp, 'systole', r, 'bPMCVSystolic');
    _copy(bp, 'diastole', r, 'bPMCVDiastolic');
    _copy(bp, 'pulse', r, 'PulseRate');
    _copy(bp, 'daqtimestamp', r, 'DAQTimestamp');
    _copy(bp, 'meatimestamp', r, 'MeasurementDateTime');
    bp['timestamp'] = ts;
    _copy(bp, 'description', r, 'MeasurementEnvironment');
    bp['device'] = deviceId;
    bp['deviceid'] = 'bloodpressure';
    return Upload('bloodpressure', [bp], from: ts, to: ts);
  }

  /// Dcont NEMERE (EID_101): type `bloodsugar`.
  static Upload? dcont(Map<String, Object?> r) {
    final ts = _localTime(r['MeasurementDateTime'], _dotDate);
    if (ts == null) return null;
    final bg = <String, Object?>{};
    _copy(bg, 'glucose_level', r, 'glValue');
    _copy(bg, 'glucose_level_unit', r, 'MeasurementUnit');
    _copy(bg, 'daqtimestamp', r, 'DAQTimestamp');
    _copy(bg, 'meatimestamp', r, 'MeasurementDateTime');
    bg['timestamp'] = ts;
    return Upload('bloodsugar', [bg], from: ts, to: ts);
  }

  /// The samples of one Savvy ECG packet (a comma separated string, or a list
  /// when the plugin reports raw data) as numbers, for the live chart.
  static List<double> ecgSamples(Object? ecgData) {
    final parts = ecgData is String
        ? ecgData.split(',')
        : (ecgData is List ? ecgData.map((e) => '$e').toList() : const <String>[]);
    return [
      for (final p in parts)
        if (double.tryParse(p.trim()) case final v?) v,
    ];
  }

  /// Polar H7 (EID_107) / demo sensor: type `pulsebelt`.
  static Map<String, Object?>? pulse(Map<String, Object?> r, {int? now}) {
    if (!r.containsKey('PulseRate')) return null;
    return {
      'pulse': r['PulseRate'],
      'timestamp': now ?? DateTime.now().millisecondsSinceEpoch,
      'device': 'EID_107',
      'deviceid': 'pulsebelt',
      'remark': '',
    };
  }
}

/// Savvy ECG (EID_103): every packet carries 14 samples (8 ms apart); the
/// server gets blocks of 1875 samples as type `ecg`. Same batching and URL as
/// the earlier app.
class SavvyEcgBatcher {
  SavvyEcgBatcher({this.channel = 'ch0'});

  static const int samplesPerBlock = 1875;
  static const int sampleDistanceMs = 8;

  final String channel;
  double _t0 = 0;
  double _ti = 0;
  double _counter = 0;
  final List<Map<String, Object?>> _out = [];
  int _count = 0;

  /// Feeds one packet. Returns the upload when a block is complete.
  Upload? add(Map<String, Object?> record) {
    final raw = record['DAQTimestamp'];
    final ts = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? double.nan;
    if (_t0 == 0) {
      if (ts <= _ti) {
        _t0 = _ti;
        _counter = 0;
      } else {
        _t0 = ts;
        _ti = ts;
        _counter = -1;
      }
    }
    final ecg = record['ECGdata'];
    if (ecg is! String) return null;
    final values = ecg.split(',');
    for (var i = 0; i < 14; i++) {
      _counter += 1;
      _ti = _t0 + _counter * sampleDistanceMs;
      if (i >= values.length) return null;
      _out.add({'timestamp': _ti.round(), channel: values[i]});
    }
    _count += 14;
    if (_count < samplesPerBlock) return null;
    final block = List<Map<String, Object?>>.of(_out);
    final n = _count;
    _out.clear();
    _count = 0;
    _t0 = 0;
    _counter = 0;
    return Upload(
      'ecg',
      block,
      from: block.first['timestamp'] as int,
      to: block.last['timestamp'] as int,
      count: n,
    );
  }

  void reset() {
    _t0 = 0;
    _ti = 0;
    _counter = 0;
    _out.clear();
    _count = 0;
  }
}

/// Collects fast one-sample records (heart rate) and uploads them together
/// every few seconds instead of one request per sample.
class BatchBuffer {
  BatchBuffer(this.type, {Duration? interval, this.maxRecords = 120, ServerClient? client})
      : interval = interval ?? Duration(seconds: AppSettings.instance.uploadSeconds),
        _client = client ?? ServerClient.instance;

  final String type;
  final Duration interval;
  final int maxRecords;
  final ServerClient _client;
  final List<Map<String, Object?>> _buf = [];
  Timer? _timer;

  void add(Map<String, Object?> record) {
    _buf.add(record);
    _timer ??= Timer.periodic(interval, (_) => flush());
    if (_buf.length >= maxRecords) flush();
  }

  Future<void> flush() async {
    if (_buf.isEmpty) return;
    final take = List<Map<String, Object?>>.of(_buf);
    _buf.clear();
    await _client.post(type, take);
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await flush();
  }
}
