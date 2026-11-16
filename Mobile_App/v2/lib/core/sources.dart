import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'device_records.dart';
import 'recorder.dart';

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

/// A source of health data. In this version there is only the demo sensor; a real
/// sensor is added by writing another [DataSource].
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

