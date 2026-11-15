import 'dart:async';
import 'dart:math';

import 'package:e77hal_plugin/e77hal_plugin.dart';
import 'package:flutter/material.dart';

import '../watch/watch_link.dart';
import '../watch/watch_protocol.dart';
import 'analysis.dart';
import 'device_records.dart';
import 'recorder.dart';
import 'server_client.dart';
import 'settings.dart';

enum SourcePhase { idle, connecting, running, problem }

/// What one data source is doing, in words an astronaut understands.
class SourceStatus {
  const SourceStatus(this.phase, this.text, {this.samples = 0, this.lastData});
  final SourcePhase phase;
  final String text;
  final int samples;
  final DateTime? lastData;

  static const idle = SourceStatus(SourcePhase.idle, 'Not started');
}

/// A source of health data (a Bluetooth sensor, the watch, the demo sensor).
abstract class DataSource {
  String get id;
  String get name;
  IconData get icon;
  final ValueNotifier<SourceStatus> status = ValueNotifier(SourceStatus.idle);

  Future<void> start();
  Future<void> stop();

  @protected
  void set(SourcePhase phase, String text, {int? samples, DateTime? lastData}) {
    final old = status.value;
    status.value = SourceStatus(
      phase,
      text,
      samples: samples ?? old.samples,
      lastData: lastData ?? old.lastData,
    );
  }

  @protected
  void gotData([int n = 1]) {
    final old = status.value;
    status.value = SourceStatus(
      SourcePhase.running,
      'Receiving data',
      samples: old.samples + n,
      lastData: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Demo sensor: simulated heart rate (the SRS starts with simulated data).

class DemoSource extends DataSource {
  DemoSource({Random? random, Recorder? recorder})
      : _rnd = random ?? Random(),
        _rec = recorder ?? Recorder.instance;

  final Random _rnd;
  final Recorder _rec;
  Timer? _timer;
  BatchBuffer? _buffer;
  double _bpm = 72;
  double _target = 72;
  double _temp = 33.4;
  int _tick = 0;

  @override
  String get id => 'demo';
  @override
  String get name => 'Demo sensor';
  @override
  IconData get icon => Icons.science_outlined;

  @override
  Future<void> start() async {
    _buffer = BatchBuffer('pulsebelt');
    _bpm = 72;
    _target = 72;
    _temp = 33.4;
    _tick = 0;
    set(SourcePhase.running, 'Simulated heart rate', samples: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  void _sample() {
    _tick++;
    if (_tick % 20 == 0) _target = 62.0 + _rnd.nextInt(30); // calm .. light effort
    _bpm += (_target - _bpm) * 0.15 + (_rnd.nextDouble() - 0.5) * 1.6;
    final now = DateTime.now();
    _buffer?.add({
      'pulse': _bpm.round().toString(),
      'timestamp': now.millisecondsSinceEpoch,
      'device': 'DEMO',
      'deviceid': 'pulsebelt',
      'remark': 'simulated',
    });
    _rec.record('hr', _bpm.roundToDouble(), time: now, source: 'demo');
    // a slow, calm skin temperature (every 5 seconds)
    _temp += (33.4 + 0.5 * sin(_tick / 240) - _temp) * 0.05 + (_rnd.nextDouble() - 0.5) * 0.04;
    if (_tick % 5 == 0) _rec.record('temp', (_temp * 10).round() / 10, time: now, source: 'demo');
    gotData();
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _buffer?.close();
    _buffer = null;
    set(SourcePhase.idle, 'Stopped');
  }
}

// ---------------------------------------------------------------------------
// Bluetooth medical devices (Savvy ECG, Beurer BM85, other BP monitors,
// Dcont NEMERE, Polar H7). The connection steps are the ones of the earlier
// app, run by the same e77hal plugin.

class BleSource extends DataSource {
  BleSource(this.deviceId, {E77hal? hal, AppSettings? settings, Recorder? recorder})
      : _hal = hal ?? E77hal(),
        _settings = settings ?? AppSettings.instance,
        _rec = recorder ?? Recorder.instance;

  final String deviceId;
  final E77hal _hal;
  final AppSettings _settings;
  final Recorder _rec;

  SavvyEcgBatcher? _ecg;
  BatchBuffer? _pulse;
  bool _on = false;
  String _lastBp = '';
  Timer? _rearm;

  @override
  String get id => deviceId;
  @override
  String get name => SensorChoice.byId(deviceId).title;
  @override
  IconData get icon => switch (deviceId) {
        'EID_107' => Icons.favorite,
        'EID_103' => Icons.monitor_heart,
        'EID_102' || 'EID_108' => Icons.speed,
        'EID_101' => Icons.bloodtype,
        _ => Icons.sensors,
      };

  /// These monitors measure only when the person presses their own button:
  /// the app collects, and takes the newest result when the monitor hangs up.
  bool get _collectOnly => deviceId == 'EID_102' || deviceId == 'EID_108';

  @override
  Future<void> start() async {
    // Same rule as the earlier app: the Savvy needs its PIN before connecting.
    if (SensorChoice.byId(deviceId).needsPin && _settings.savvyPin.trim().isEmpty) {
      set(SourcePhase.problem, 'Enter the PIN of the ECG recorder in Settings first.');
      return;
    }
    _on = true;
    _lastBp = '';
    _ecg = SavvyEcgBatcher(channel: _settings.ecgChannel);
    _pulse = BatchBuffer('pulsebelt');
    _hal.onStatus = (m) {
      AppLog.add(name, m);
      if (_on) set(SourcePhase.connecting, m);
    };
    _hal.onError = (m) {
      AppLog.add(name, 'problem: $m');
      if (_on) set(SourcePhase.problem, m);
    };
    _hal.onLog = (m) => AppLog.add(name, m);
    _hal.onReportData = _onData;
    _hal.onReportEvent = _onEvent;
    _begin();
  }

  void _begin() {
    set(SourcePhase.connecting, 'Looking for your sensor …');
    final params = {'deviceID': deviceId, 'pinNumber': _settings.savvyPin.trim()};
    final run = _collectOnly ? _hal.startMeasurementx(params) : _hal.startMeasurement(params);
    run.catchError((Object e) {
      AppLog.add(name, 'could not start: $e');
      set(SourcePhase.problem, 'Could not start the sensor.');
      return <String, Object?>{};
    });
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

  void _onData(Map<String, Object?> r) {
    if (!_on) return;
    Upload? up;
    switch (deviceId) {
      case 'EID_103':
        up = _ecg?.add(r);
        _rec.addEcgSamples(DeviceRecords.ecgSamples(r['ECGdata'])); // live chart
        gotData(14);
      case 'EID_102' || 'EID_108':
        final key = '${r['MeasurementDateTime']}';
        if (key == _lastBp) return; // same measurement as before
        _lastBp = key;
        up = DeviceRecords.beurer(r, deviceId: deviceId);
        final sys = _num(r['bPMCVSystolic']);
        final dia = _num(r['bPMCVDiastolic']);
        final t = up?.from == null ? null : DateTime.fromMillisecondsSinceEpoch(up!.from!);
        if (sys != null && dia != null) {
          _rec.recordBloodPressure(sys, dia, time: t, source: deviceId);
        }
        final pulse = _num(r['PulseRate']);
        if (pulse != null && pulse > 0) _rec.record('hr', pulse, time: t, source: deviceId);
        gotData();
      case 'EID_101':
        up = DeviceRecords.dcont(r);
        var g = _num(r['glValue']);
        if (g != null) {
          final unit = '${r['MeasurementUnit']}'.toLowerCase();
          if (unit.contains('mg')) g = g / 18.016; // ranges are in mmol/L
          _rec.record('glu', g,
              time: up?.from == null ? null : DateTime.fromMillisecondsSinceEpoch(up!.from!), source: deviceId);
        }
        gotData();
      case 'EID_107':
        final p = DeviceRecords.pulse(r);
        if (p != null) {
          _pulse?.add(p);
          final v = _num(r['PulseRate']);
          if (v != null) _rec.record('hr', v, source: deviceId);
        }
        gotData();
    }
    if (up != null) {
      ServerClient.instance.post(up.type, up.records, from: up.from, to: up.to, count: up.count);
    }
  }

  void _onEvent(Map<String, Object?> e) {
    if (!_on || e['key'] != 'EV_1005') return;
    if (_collectOnly) {
      // The monitor closes the link by itself after sending: take the newest
      // measurement, then wait for the next one.
      _hal.readLastMeasurements({'deviceID': deviceId, 'amount': 1});
      _rearm?.cancel();
      _rearm = Timer(const Duration(seconds: 3), () async {
        if (!_on) return;
        await _hal.stopMeasurement({'deviceID': deviceId});
        if (_on) _begin();
      });
      set(SourcePhase.running, 'Measurement received. Waiting for the next one.');
    } else if (deviceId != 'EID_103') {
      set(SourcePhase.problem, 'The sensor disconnected. Press STOP and START to reconnect.');
    } else {
      // Savvy reconnects by itself
      set(SourcePhase.connecting, 'Connection lost. Reconnecting …');
    }
  }

  @override
  Future<void> stop() async {
    _on = false;
    _rearm?.cancel();
    try {
      await _hal.stopMeasurement({'deviceID': deviceId});
    } catch (_) {}
    await _pulse?.close();
    _pulse = null;
    _ecg = null;
    set(SourcePhase.idle, 'Stopped');
  }
}

// ---------------------------------------------------------------------------
// Galaxy Watch (via the watch companion app)

class WatchSource extends DataSource {
  WatchSource({WatchLink? link, Recorder? recorder})
      : _link = link ?? WatchLink.instance,
        _rec = recorder ?? Recorder.instance;

  final WatchLink _link;
  final Recorder _rec;
  bool _on = false;
  Timer? _poll;

  @override
  String get id => 'watch';
  @override
  String get name => 'Galaxy Watch';
  @override
  IconData get icon => Icons.watch;

  @override
  Future<void> start() async {
    _on = true;
    _link.addListener(_update);
    _link.onFrame = handleFrame;
    await _link.load();
    if (_link.savedAddress == null) {
      set(SourcePhase.problem, 'The watch is not paired yet. Open Settings and pair the watch.');
      return;
    }
    set(SourcePhase.connecting, 'Connecting to the watch …');
    await _link.connectSaved();
    // The link ends by itself when the watch goes away: look again from time to time.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_on && _link.phase == WatchPhase.failed && _link.savedAddress != null) {
        _link.connectSaved();
      }
    });
    _update();
  }

  /// Last second stored per data type (slow sensors are kept at 1 value per second).
  final Map<String, int> _lastSecond = {};

  /// One data frame from the watch: every data type is stored (and so charted).
  @visibleForTesting
  void handleFrame(WatchParam p, WatchFrame f) {
    if (p.id == 'hr' || p.id == 'shr') {
      for (final s in f.samples) {
        final bpm = s.values.isEmpty ? null : s.values[0];
        if (bpm != null && bpm > 0) {
          _rec.record('hr', bpm, time: DateTime.fromMillisecondsSinceEpoch(s.timeMs), source: 'watch');
        }
      }
      return;
    }
    // Every other data type the watch delivers gets its own chart. Fast
    // waveforms (ECG, PPG at 100 Hz and more) are not drawn as a plain line.
    if (p.rateHz >= 100) return;
    final multi = p.fields.length > 1;
    for (final s in f.samples) {
      final sec = s.timeMs ~/ 1000;
      if (_lastSecond[p.id] == sec) continue;
      _lastSecond[p.id] = sec;
      for (var i = 0; i < p.fields.length && i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final id = multi ? 'w_${p.id}_${p.fields[i]}' : 'w_${p.id}';
        _rec.registerParam(ParamDef.plain(
          id: id,
          name: multi ? '${p.name} ${p.fields[i]}' : p.name,
          unit: p.unit,
        ));
        _rec.record(id, v, time: DateTime.fromMillisecondsSinceEpoch(s.timeMs), source: 'watch');
      }
    }
  }

  void _update() {
    if (!_on) return;
    switch (_link.phase) {
      case WatchPhase.ready:
        // Read and send everything the watch can deliver reliably.
        final ids = _link.params.where((p) => p.available).map((p) => p.id).toSet();
        for (final id in ids) {
          if (!_link.reading.contains(id)) _link.setReading(id, true);
          if (!_link.uploading.contains(id)) _link.setUploading(id, true);
        }
        final n = _link.received.values.fold<int>(0, (a, b) => a + b);
        if (_link.lastDataAt != null) {
          set(SourcePhase.running, 'Receiving data', samples: n, lastData: _link.lastDataAt);
        } else {
          set(SourcePhase.running, ids.isEmpty ? 'Connected. No sensor available.' : 'Connected. Waiting for data …');
        }
      case WatchPhase.failed:
        set(SourcePhase.problem, _link.message);
      case WatchPhase.needApproval:
      case WatchPhase.waitingApproval:
        set(SourcePhase.problem, 'The watch is not paired. Open Settings and pair the watch.');
      default:
        set(SourcePhase.connecting, _link.message.isEmpty ? 'Connecting to the watch …' : _link.message);
    }
  }

  @override
  Future<void> stop() async {
    _on = false;
    _poll?.cancel();
    _link.removeListener(_update);
    _link.onFrame = null;
    for (final id in _link.reading.toList()) {
      await _link.setReading(id, false);
    }
    await _link.disconnect();
    set(SourcePhase.idle, 'Stopped');
  }
}
