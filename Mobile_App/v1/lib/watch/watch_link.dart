import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:e77hal_plugin/e77hal_plugin.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'watch_protocol.dart';
import 'watch_uploader.dart';

enum WatchPhase {
  idle,
  scanning,
  connecting,
  needApproval, // watch has no phone yet: user has to press "Pair"
  waitingApproval, // code shown, the user must confirm on the watch
  ready,
  failed,
}

/// Key/value storage of the link settings.
abstract class WatchStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

class PreferencesWatchStore implements WatchStore {
  @override
  Future<String?> get(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> set(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

/// Connection to the watch companion app: scan, connect, bond, pair (approval
/// on the watch), list parameters, switch them on/off, receive the data and
/// hand the selected parameters to the [WatchUploader].
class WatchLink extends ChangeNotifier {
  WatchLink({BleTransport? transport, WatchStore? store, WatchUploader? uploader})
      : _transport = transport ?? ReactiveBleTransport(),
        _store = store ?? PreferencesWatchStore(),
        uploader = uploader ?? WatchUploader() {
    this.uploader.onLog = _log;
  }

  static final WatchLink instance = WatchLink();

  static const _kId = 'watchPhoneId';
  static const _kAddress = 'watchAddress';
  static const _kName = 'watchName';
  static const _kRead = 'watchRead';
  static const _kUpload = 'watchUpload';

  final BleTransport _transport;
  final WatchStore _store;
  final WatchUploader uploader;

  // ---- public state -----------------------------------------------------------------

  WatchPhase phase = WatchPhase.idle;
  String message = '';
  String? pairCode;
  bool pairingClosed = false;
  String watchName = '';
  String? savedAddress;
  final List<BleScanResult> found = [];
  final List<WatchParam> params = [];
  final Set<String> reading = {}; // what the user wants the watch to read
  final Set<String> active = {}; // what the watch confirmed
  final Set<String> uploading = {}; // what is sent to the server
  final Map<String, String> errors = {};
  final Map<String, WatchSample> latest = {};
  final Map<String, int> received = {};
  int mtu = 23;

  /// What the watch told about itself in its last "state" message.
  int watchAppCode = 0;
  String watchAppName = '';
  String watchModel = '';
  int watchOs = 0;

  /// Number of record names the watch accepted in the "deal".
  int dealCount = 0;


  /// Called for every data frame (the app uses it for its own charts).
  void Function(WatchParam param, WatchFrame frame)? onFrame;

  final List<LogLine> logLines = [];
  DateTime? lastDataAt;
  int drops = 0;

  void _log(String level, String text) {
    logLines.add(LogLine(DateTime.now(), level, text));
    if (logLines.length > 400) logLines.removeRange(0, logLines.length - 400);
  }

  void clearLog() {
    logLines.clear();
    _notify();
  }

  // ---- internals ----------------------------------------------------------------------

  String? _address;
  String _phoneId = '';
  StreamSubscription<BleScanResult>? _scanSub;
  StreamSubscription<BleLinkEvent>? _linkSub;
  StreamSubscription<List<int>>? _evSub;
  StreamSubscription<List<int>>? _dataSub;
  Timer? _ping;
  bool _loaded = false;
  int _session = 0;
  bool _disposed = false;

  bool get connected => phase == WatchPhase.ready;
  WatchParam? param(String id) {
    for (final p in params) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _set(WatchPhase p, [String m = ""]) {
    if (p != phase || m != message) {
      _log(p == WatchPhase.failed ? "error" : "state",
          "${_phaseName(p)}${m.isEmpty ? "" : " - $m"}");
    }
    phase = p;
    message = m;
    _notify();
  }

  static String _phaseName(WatchPhase p) => switch (p) {
        WatchPhase.idle => "Idle",
        WatchPhase.scanning => "Scanning",
        WatchPhase.connecting => "Connecting",
        WatchPhase.needApproval => "Pairing needed",
        WatchPhase.waitingApproval => "Waiting for approval on the watch",
        WatchPhase.ready => "Connected",
        WatchPhase.failed => "Problem",
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ---- settings -------------------------------------------------------------------------

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _phoneId = await _store.get(_kId) ?? '';
    if (_phoneId.isEmpty) {
      final r = Random.secure();
      _phoneId = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _store.set(_kId, _phoneId);
    }
    final a = await _store.get(_kAddress);
    savedAddress = (a == null || a.isEmpty) ? null : a;
    watchName = await _store.get(_kName) ?? '';
    reading
      ..clear()
      ..addAll(_ids(await _store.get(_kRead)));
    uploading
      ..clear()
      ..addAll(_ids(await _store.get(_kUpload)));
    uploader.setEnabled(uploading);
    _notify();
  }

  static List<String> _ids(String? json) {
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List).map((e) => '$e').toList();
    } catch (_) {
      return const [];
    }
  }

  // ---- scanning -------------------------------------------------------------------------

  Future<void> startScan() async {
    await load();
    await _teardown();
    found.clear();
    _set(WatchPhase.scanning, 'Looking for your watch …');
    final problem = await _transport.prepare();
    if (problem != null) {
      _set(WatchPhase.failed, problem);
      return;
    }
    _scanSub = _transport.scan(withServices: [WatchProtocol.service]).listen((r) {
      final i = found.indexWhere((x) => x.address == r.address);
      if (i >= 0) {
        found[i] = r;
      } else {
        found.add(r);
        _log('info', 'found ${r.name.isEmpty ? 'device' : r.name} ${r.address} (${r.rssi} dBm)');
      }
      _notify();
    }, onError: (Object e) => _set(WatchPhase.failed, 'Scan failed: $e'));
    Timer(const Duration(seconds: 25), () {
      if (phase == WatchPhase.scanning) stopScan();
    });
  }

  void stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    if (phase == WatchPhase.scanning) {
      _set(WatchPhase.idle,
          found.isEmpty ? 'No watch found. Open the health companion app on the watch.' : '');
    }
  }

  // ---- connecting -------------------------------------------------------------------------

  Future<void> connectSaved() async {
    await load();
    final a = savedAddress;
    if (a != null) await connect(a);
  }

  Future<void> connect(String address, {String? name}) async {
    await load();
    await _teardown();
    final session = ++_session;
    _address = address;
    if (name != null && name.isNotEmpty) watchName = name;
    _set(WatchPhase.connecting, 'Connecting ...');
    final problem = await _transport.prepare();
    if (problem != null) {
      _set(WatchPhase.failed, problem);
      return;
    }
    _linkSub = _transport.connect(address).listen((e) {
      if (session != _session) return;
      if (e.state == BleLinkState.connected) {
        _handshake(address, session);
      } else {
        _lost(session, e.error);
      }
    }, onError: (Object e) {
      if (session == _session) _lost(session, '$e');
    });
  }

  void _lost(int session, String? why) {
    if (session != _session) return;
    drops++;
    _cleanup();
    _set(WatchPhase.failed,
        'The connection to the watch ended${why == null || why.isEmpty ? '' : ': $why'}');
  }

  Future<void> _handshake(String address, int session) async {
    try {
      _set(WatchPhase.connecting, 'Setting up the link ...');
      // 1. bigger frames
      try {
        mtu = await _transport.requestMtu(address, WatchProtocol.wantedMtu);
      } catch (_) {
        mtu = 23;
      }
      if (mtu < WatchProtocol.minMtu) {
        throw StateError('The Bluetooth packet size ($mtu) is too small for sensor data.');
      }
      // 2. OS pairing (encryption) - the watch only accepts encrypted access
      if (await _transport.bondState(address) != BondState.bonded) {
        _set(WatchPhase.connecting,
            'Confirm the Bluetooth pairing request on the phone and on the watch ...');
        final bonded = _transport
            .watchBond(address)
            .firstWhere((s) => s == BondState.bonded)
            .timeout(const Duration(seconds: 60));
        if (!await _transport.createBond(address)) {
          throw StateError('Android did not start the Bluetooth pairing.');
        }
        await bonded;
        if (session != _session) return;
      }
      await _transport.discoverServices(address);
      if (session != _session) return;
      // 3. listen, then say hello
      _evSub = _transport
          .subscribe(address, WatchProtocol.service, WatchProtocol.events)
          .listen(_onEvent, onError: (Object e) => _lost(session, '$e'));
      _dataSub = _transport
          .subscribe(address, WatchProtocol.service, WatchProtocol.data)
          .listen(_onData, onError: (Object e) => _lost(session, '$e'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await savedConnection(address);
      await _send(WatchProtocol.hello(_phoneId, 'SpaceMedX phone'));
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        _send(WatchProtocol.ping()).catchError((_) {});
      });
    } catch (e) {
      if (session != _session) return;
      _cleanup();
      _set(WatchPhase.failed, '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> savedConnection(String address) async {
    savedAddress = address;
    await _store.set(_kAddress, address);
    if (watchName.isNotEmpty) await _store.set(_kName, watchName);
  }

  Future<void> _send(Map<String, Object?> m) {
    final a = _address;
    if (a == null) return Future.value();
    _log('info', 'to watch: ${m['m']}${m['p'] == null ? '' : ' ${m['p']}'}');
    return _transport.write(
        a, WatchProtocol.service, WatchProtocol.control, WatchProtocol.encode(m));
  }

  // ---- events from the watch ----------------------------------------------------------------

  void _onEvent(List<int> bytes) {
    final m = WatchProtocol.decode(bytes);
    if (m == null) return;
    _log('info', 'from watch: ${m['m']}${m['s'] == null ? '' : ' (${m['s']})'}${m['id'] == null ? '' : ' ${m['id']}'}${m['msg'] == null ? '' : ': ${m['msg']}'}');
    switch (m['m']) {
      case 'state':
        _onState(m);
        break;
      case 'pair_code':
        pairCode = '${m['code']}';
        _set(WatchPhase.waitingApproval, 'Confirm on the watch that it shows this code.');
        break;
      case 'pair_result':
        pairCode = null;
        if (m['ok'] != true) {
          _set(WatchPhase.needApproval, 'The pairing was declined on the watch.');
        }
        break; // approved: a "ready" state follows
      case 'param':
        final p = WatchParam.fromMessage(m);
        if (p.srv.isNotEmpty) uploader.negotiated.putIfAbsent(p.id, () => p.srv);
        // only sensors that certainly work end to end are shown
        if (!p.available || !uploader.isConfirmed(p.id)) break;
        params.removeWhere((x) => x.id == p.id);
        params.add(p);
        break;
      case 'params_end':
        _onParamsEnd();
        break;
      case 'active':
        active
          ..clear()
          ..addAll(((m['p'] ?? const []) as List).map((e) => '$e'));
        _notify();
        break;
      case 'err':
        errors['${m['id']}'] = '${m['msg']}';
        _notify();
        break;
      case 'deal_ack':
        dealCount = (m['n'] as num?)?.toInt() ?? 0;
        _log('info', 'the watch accepted $dealCount record name(s)');
        _notify();
        break;
      default:
        break;
    }
  }

  void _onState(Map<String, dynamic> m) {
    final n = m['name'];
    if (n is String && n.isNotEmpty) watchName = n;
    watchAppCode = (m['app'] as num?)?.toInt() ?? watchAppCode;
    watchAppName = '${m['appName'] ?? watchAppName}';
    watchModel = '${m['model'] ?? watchModel}';
    watchOs = (m['os'] as num?)?.toInt() ?? watchOs;
    pairingClosed = false;
    switch (m['s']) {
      case 'ready':
        pairCode = null;
        params.clear();
        _send(WatchProtocol.listParams());
        _set(WatchPhase.connecting, 'Reading the sensor list ...');
        break;
      case 'need_pairing':
        _set(WatchPhase.needApproval, 'This watch is not linked to a phone yet.');
        break;
      case 'pairing_closed':
        pairingClosed = true;
        _set(WatchPhase.needApproval,
            'Pairing is only possible while the watch companion app is open on the watch.');
        break;
      case 'other_phone':
        _cleanup();
        _set(WatchPhase.failed,
            'The watch is linked to another phone. Use "Forget phone" in the watch app first.');
        break;
      case 'version':
        _cleanup();
        _set(WatchPhase.failed, 'The watch app has a different protocol version. Update both apps.');
        break;
    }
  }

  void _onParamsEnd() {
    errors.clear();
    final available = {for (final p in params) if (p.available) p.id};
    reading.removeWhere((id) => !available.contains(id));
    _set(WatchPhase.ready);
    _sendDeal();
    if (reading.isNotEmpty) _pushSelection();
  }

  /// Agrees with the watch on the record names: for every data type of the
  /// watch the server record type and the value names used in the upload.
  Future<void> _sendDeal() async {
    final items = <Map<String, Object?>>[];
    for (final p in params) {
      if (p.srv.isNotEmpty && !WatchUploader.serverTypes.containsKey(p.id)) {
        uploader.negotiated[p.id] = p.srv; // unknown here: take the watch's name
      }
      items.add({'id': p.id, 'srv': uploader.typeFor(p.id), 'f': WatchUploader.fieldsFor(p)});
    }
    _log('info', 'deal: ${items.map((e) => '${e['id']}=${e['srv']}').join(', ')}');
    try {
      await _send(WatchProtocol.deal(items));
    } catch (_) {}
  }

  void _onData(List<int> bytes) {
    final m = WatchProtocol.decode(bytes);
    if (m == null) return;
    final frame = WatchFrame.parse(m, (id) => param(id)?.fields.length ?? 0);
    if (frame == null || frame.samples.isEmpty) return;
    final p = param(frame.paramId);
    if (p == null) return;
    latest[p.id] = frame.samples.last;
    received[p.id] = (received[p.id] ?? 0) + frame.samples.length;
    lastDataAt = DateTime.now();
    if (received[p.id] == frame.samples.length) {
      _log('data', 'first data of ${p.id}: ${frame.samples.last.values}');
    }
    uploader.add(p, frame);
    onFrame?.call(p, frame);
    _notify();
  }

  // ---- user actions ------------------------------------------------------------------------------

  /// Asks the watch to link with this phone (the user then approves there).
  Future<void> requestPairing() async {
    await _send(WatchProtocol.pair(_phoneId, 'SpaceMedX phone'));
  }

  Future<void> setReading(String id, bool on) async {
    if (on) {
      reading.add(id);
    } else {
      reading.remove(id);
      latest.remove(id);
      received.remove(id);
      errors.remove(id);
      await setUploading(id, false);
    }
    _log('info', 'Read $id: ${on ? 'on' : 'off'}');
    await _store.set(_kRead, jsonEncode(reading.toList()));
    _notify();
    await _pushSelection();
  }

  Future<void> setUploading(String id, bool on) async {
    if (on) {
      uploading.add(id);
    } else {
      uploading.remove(id);
    }
    uploader.setEnabled(uploading);
    _log('info', 'Send to server $id: ${on ? 'on' : 'off'}');
    await _store.set(_kUpload, jsonEncode(uploading.toList()));
    _notify();
    await _pushSelection();
  }

  Future<void> _pushSelection() async {
    if (_address == null || phase != WatchPhase.ready) return;
    errors.removeWhere((id, _) => !reading.contains(id));
    await _send(WatchProtocol.setActive(reading, uploading));
  }

  /// Removes the link on the watch and forgets it here.
  Future<void> unpair() async {
    try {
      await _send(WatchProtocol.unpair());
    } catch (_) {}
    await disconnect();
    savedAddress = null;
    await _store.set(_kAddress, '');
  }

  Future<void> disconnect() async {
    await uploader.flush();
    await _teardown();
    _set(WatchPhase.idle);
  }

  // ---- cleanup --------------------------------------------------------------------------------------

  void _cleanup() {
    _ping?.cancel();
    _ping = null;
    _evSub?.cancel();
    _dataSub?.cancel();
    _evSub = null;
    _dataSub = null;
    _linkSub?.cancel(); // cancelling the connection stream disconnects
    _linkSub = null;
    active.clear();
    pairCode = null;
  }

  Future<void> _teardown() async {
    _session++;
    _scanSub?.cancel();
    _scanSub = null;
    _cleanup();
    _address = null;
  }
}

/// One line of the watch log.
class LogLine {
  const LogLine(this.time, this.level, this.text);
  final DateTime time;
  final String level;
  final String text;
}
