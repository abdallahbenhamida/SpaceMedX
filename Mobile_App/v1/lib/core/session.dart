import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'recorder.dart';
import 'server_client.dart';
import 'settings.dart';
import 'sources.dart';

/// The big picture shown on the Home screen.
enum SessionState { stopped, starting, running, attention }

/// One START / STOP of the astronaut: starts every chosen data source,
/// keeps the app alive in the background and retries uploads, until STOP.
class MonitorSession extends ChangeNotifier {
  MonitorSession({
    AppSettings? settings,
    ServerClient? server,
    List<DataSource> Function(AppSettings s)? sourceFactory,
    this.useAwakeChannel = true,
  })  : _settings = settings ?? AppSettings.instance,
        _server = server ?? ServerClient.instance,
        _factory = sourceFactory ?? defaultSources;

  static final MonitorSession instance = MonitorSession();

  /// Builds the sources the astronaut chose in Setup.
  static List<DataSource> defaultSources(AppSettings s) => [
        if (s.useWatch) WatchSource(),
        if (s.sensor == 'demo') DemoSource(),
        if (s.sensor.startsWith('EID_')) BleSource(s.sensor),
      ];

  static const MethodChannel _awake = MethodChannel('spacemedx/awake');

  final AppSettings _settings;
  final ServerClient _server;
  final List<DataSource> Function(AppSettings) _factory;
  final bool useAwakeChannel;

  List<DataSource> sources = [];
  bool _running = false;
  DateTime? startedAt;
  Timer? _retry;
  Timer? _tick;

  bool get isRunning => _running;

  /// Why START did nothing (shown to the astronaut), or null.
  String? get cannotStartReason {
    // the server is optional: without one the data stays on the phone
    if (_factory(_settings).isEmpty) return 'Choose a sensor or the watch in Settings.';
    return null;
  }

  SessionState get state {
    if (!_running) return SessionState.stopped;
    // only a problem with a sensor counts here: a server problem is shown
    // separately and says nothing about the astronaut's health
    if (sources.any((s) => s.status.value.phase == SourcePhase.problem)) {
      return SessionState.attention;
    }
    if (sources.every((s) => s.status.value.phase == SourcePhase.running)) {
      return SessionState.running;
    }
    return SessionState.starting;
  }

  Duration get elapsed => startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  Future<void> start() async {
    if (_running || cannotStartReason != null) return;
    _running = true;
    startedAt = DateTime.now();
    _server.resetStats();
    Recorder.instance.resetLive();
    sources = _factory(_settings);
    for (final s in sources) {
      s.status.addListener(_changed);
    }
    _server.stats.addListener(_changed);
    _keepAwake(true);
    _retry = Timer.periodic(const Duration(seconds: 15), (_) => _server.flushQueue());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
    // start the sources one after the other: Bluetooth does not like parallel scans
    for (final s in sources) {
      if (!_running) break;
      try {
        await s.start();
      } catch (e) {
        AppLog.add(s.name, 'could not start: $e');
        s.status.value = SourceStatus(SourcePhase.problem, 'Could not start the sensor.');
      }
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _retry?.cancel();
    _tick?.cancel();
    notifyListeners();
    for (final s in sources) {
      try {
        await s.stop();
      } catch (_) {}
      s.status.removeListener(_changed);
    }
    _server.stats.removeListener(_changed);
    await _server.flushQueue();
    _keepAwake(false);
    notifyListeners();
  }

  void _changed() => notifyListeners();

  void _keepAwake(bool on) {
    if (!useAwakeChannel) return;
    final names = sources.map((s) => s.name).join(', ');
    _awake
        .invokeMethod<bool>('set', {
          'on': on,
          'screenOn': _settings.keepScreenOn,
          'text': on ? tr('Collecting data: {names}', {'names': names}) : '',
        })
        .catchError((Object _) => false);
  }
}
