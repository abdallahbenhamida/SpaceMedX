import 'dart:async';

import 'server_client.dart';
import 'settings.dart';

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
