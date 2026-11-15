import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'local_store.dart';
import 'settings.dart';

/// What the astronaut sees about the connection to the server.
class UploadStats {
  const UploadStats({
    this.sent = 0,
    this.waiting = 0,
    this.lastOk,
    this.lastError,
    this.errorKey,
    this.errorArgs,
  });
  final int sent; // records the server accepted
  final int waiting; // records kept on the phone until the server is reachable
  final DateTime? lastOk;
  final String? lastError; // null = last attempt worked (English, for logs and tests)
  final String? errorKey; // English key of the message, for tr()
  final Map<String, Object>? errorArgs;

  /// The problem in the language of the app (null = none).
  String? get errorText => errorKey == null ? null : tr(errorKey!, errorArgs);

  UploadStats copy({
    int? sent,
    int? waiting,
    DateTime? lastOk,
    String? errorKey,
    Map<String, Object>? errorArgs,
    bool clearError = false,
  }) =>
      UploadStats(
        sent: sent ?? this.sent,
        waiting: waiting ?? this.waiting,
        lastOk: lastOk ?? this.lastOk,
        lastError: clearError ? null : (errorKey != null ? _fill(errorKey, errorArgs) : lastError),
        errorKey: clearError ? null : (errorKey ?? this.errorKey),
        errorArgs: clearError ? null : (errorKey != null ? errorArgs : this.errorArgs),
      );

  static String _fill(String key, Map<String, Object>? args) {
    var s = key;
    args?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

class _Pending {
  _Pending(this.url, this.body, this.records, this.label, [this.id]);
  int? id; // row in the local store (so it survives a restart)
  final String url;
  final String body;
  final int records;
  final String label;
}

/// Posts data to the server exactly like the earlier app does:
///
/// `POST {server}{userId}/{type}/{n}/{from}/{to}?profil=0&deviceid=0&ext=1`,
/// `Content-Type: application/x-www-form-urlencoded`, body = JSON text
/// (an array of records), no authorisation header.
///
/// Data that cannot be delivered (no network, server down) is kept on the
/// phone and retried, so nothing is lost while the link is down.
class ServerClient {
  ServerClient({http.Client? client, this.store}) : _client = client ?? http.Client();

  /// Where waiting batches are kept (set at start-up).
  LocalStore? store;

  /// Test hook: false = keep everything on the phone, send nothing.
  bool Function()? sendEnabledOverride;
  bool get _sendEnabled =>
      (sendEnabledOverride ?? () => AppSettings.instance.sendToServer && _base.isNotEmpty && _user.isNotEmpty)();

  static final ServerClient instance = ServerClient();

  /// Same headers as the WebView of the earlier app sent (the server was
  /// built for them).
  static const Map<String, String> _headers = {
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    'Accept': '*/*',
    'Origin': 'https://localhost',
    'Referer': 'https://localhost/',
    'X-Requested-With': 'com.obuda.biotech.drhealthv2',
  };

  static const String _query = '?profil=0&deviceid=0&ext=1';

  /// Oldest data is dropped when more than this many batches are waiting.
  static const int maxQueuedBatches = 2000;

  final http.Client _client;
  final ValueNotifier<UploadStats> stats = ValueNotifier(const UploadStats());
  final List<_Pending> _queue = [];
  bool _flushing = false;

  /// Test hook / overrides.
  String Function()? baseOverride;
  String Function()? userOverride;

  String get _base => (baseOverride ?? () => AppSettings.normalizeBase(AppSettings.instance.serverUrl))();
  String get _user => (userOverride ?? () => AppSettings.instance.userId.trim())();

  /// Loads the batches that were waiting when the app was closed.
  Future<void> restore() async {
    final s = store;
    if (s == null) return;
    for (final b in await s.queue()) {
      _queue.add(_Pending(b.url, b.body, b.records, b.label, b.id));
    }
    stats.value = stats.value.copy(waiting: _queue.fold<int>(0, (a, b) => a + b.records));
  }

  void resetStats() {
    // the waiting batches stay: only the counters of this session restart
    stats.value = UploadStats(waiting: _queue.fold<int>(0, (a, b) => a + b.records));
  }

  void _set(UploadStats s) => stats.value = s;

  /// Sends [records] as type [type]. [from] / [to] are the time span of the
  /// data in epoch milliseconds (default: now). Returns true when the server
  /// accepted the data; otherwise the data is queued for a later retry.
  Future<bool> post(
    String type,
    List<Map<String, Object?>> records, {
    int? from,
    int? to,
    int? count,
  }) async {
    // no server (or sending switched off): the data simply stays on the phone
    if (records.isEmpty || !_sendEnabled) return true;
    final base = _base;
    final user = _user;
    if (base.isEmpty || user.isEmpty) {
      _set(stats.value.copy(errorKey: 'Server address or user ID is missing. Open Settings.'));
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final url = '$base$user/$type/${count ?? 1}/${from ?? now}/${to ?? from ?? now}$_query';
    final p = _Pending(url, jsonEncode(records), records.length, type);
    final result = await _try(p);
    if (result == _Result.ok) {
      // the link works: deliver what was waiting
      unawaited(flushQueue());
      return true;
    }
    if (result == _Result.retry) _enqueue(p);
    return false;
  }

  void _enqueue(_Pending p) {
    _queue.add(p);
    store?.enqueue(p.url, p.body, p.records, p.label).then((id) => p.id = id);
    while (_queue.length > maxQueuedBatches) {
      final old = _queue.removeAt(0);
      if (old.id != null) store?.dequeue(old.id!);
    }
    _set(stats.value.copy(waiting: _queue.fold<int>(0, (a, b) => a + b.records)));
  }

  /// Tries to deliver the batches that are waiting.
  Future<void> flushQueue() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final p = _queue.first;
        final r = await _try(p, fromQueue: true);
        if (r == _Result.retry) break; // still down: try again later
        _queue.removeAt(0); // delivered, or rejected for good
        if (p.id != null) await store?.dequeue(p.id!);
      }
    } finally {
      _flushing = false;
      _set(stats.value.copy(waiting: _queue.fold<int>(0, (a, b) => a + b.records)));
    }
  }

  Future<_Result> _try(_Pending p, {bool fromQueue = false}) async {
    try {
      final res = await _client
          .post(Uri.parse(p.url), headers: _headers, body: utf8.encode(p.body))
          .timeout(const Duration(seconds: 30));
      final code = res.statusCode;
      if (code >= 200 && code < 300) {
        _set(stats.value.copy(
          sent: stats.value.sent + p.records,
          lastOk: DateTime.now(),
          clearError: true,
        ));
        return _Result.ok;
      }
      _set(stats.value.copy(errorKey: _httpKey(code), errorArgs: {'code': code}));
      debugPrint('upload ${p.label} failed: HTTP $code ${p.url}');
      // 4xx: the server refuses this data, sending it again would not help
      return (code >= 400 && code < 500 && code != 408 && code != 429)
          ? _Result.rejected
          : _Result.retry;
    } catch (e) {
      debugPrint('upload ${p.label} failed: $e');
      _set(stats.value.copy(errorKey: 'The server cannot be reached. Data is kept on the phone.'));
      return _Result.retry;
    }
  }

  static String _httpKey(int code) {
    if (code == 404) return 'The server answered "not found" (404). Check the server address and the user ID.';
    if (code == 401 || code == 403) return 'The server did not accept this phone ({code}).';
    if (code >= 500) return 'The server has a problem ({code}). Data is kept on the phone.';
    return 'The server refused the data (HTTP {code}).';
  }

  /// "Test connection" in Setup: is something answering at that address?
  /// (A test record is not sent, so nothing is stored on the server.)
  Future<({bool ok, String message})> testConnection(String serverUrl) async {
    final base = AppSettings.normalizeBase(serverUrl);
    if (base.isEmpty) return (ok: false, message: tr('Enter the server address first.'));
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) {
      return (ok: false, message: tr('This does not look like a server address.'));
    }
    try {
      await _client.get(uri, headers: {'Accept': '*/*'}).timeout(const Duration(seconds: 10));
      return (ok: true, message: tr('The server answers.'));
    } on TimeoutException {
      return (ok: false, message: tr('No answer from the server (timeout).'));
    } catch (_) {
      return (ok: false, message: tr('Cannot reach the server. Check the address and the network.'));
    }
  }
}

enum _Result { ok, retry, rejected }
