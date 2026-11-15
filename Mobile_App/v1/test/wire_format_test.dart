import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacemedx/core/device_records.dart';
import 'package:spacemedx/core/server_client.dart';

// Not a widget test: a real local HTTP server receives what the app sends, so
// the wire format in the server guide (SERVER_GUIDE.md) is checked for real.
void main() {
  test('what a server receives', () async {
    final seen = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final headers = <String, String>{};
      req.headers.forEach((k, v) => headers[k] = v.join(','));
      seen.add({'method': req.method, 'uri': req.uri.toString(), 'headers': headers, 'body': body});
      req.response.statusCode = 200;
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final c = ServerClient()
      ..baseOverride = (() => 'http://127.0.0.1:${server.port}/measurement/save/')
      ..userOverride = (() => '1234')
      ..sendEnabledOverride = (() => true);

    // heart rate (Polar H7 record, batched like the app does)
    final p = DeviceRecords.pulse({'PulseRate': 72}, now: 1790000000000)!;
    expect(await c.post('pulsebelt', [p]), isTrue);

    // blood pressure (Beurer BM85 / standard BP monitor)
    final bp = DeviceRecords.beurer({
      'bPMCVSystolic': 121,
      'bPMCVDiastolic': 79,
      'PulseRate': 66,
      'DAQTimestamp': 1790000000000,
      'MeasurementDateTime': '2026/11/14 8:30:00',
      'MeasurementEnvironment': 'at rest',
    })!;
    expect(await c.post(bp.type, bp.records, from: bp.from, to: bp.to, count: bp.count), isTrue);

    // glucose (Dcont NEMERE)
    final g = DeviceRecords.dcont({
      'glValue': 5.4,
      'MeasurementUnit': 'mmol/L',
      'DAQTimestamp': 1790000000000,
      'MeasurementDateTime': '2026.11.14. 8:31',
    })!;
    expect(await c.post(g.type, g.records, from: g.from, to: g.to, count: g.count), isTrue);

    // ECG block (Savvy)
    final b = SavvyEcgBatcher();
    Upload? ecg;
    for (var i = 0; ecg == null; i++) {
      ecg = b.add({
        'DAQTimestamp': 1790000000000 + i * 112,
        'ECGdata': List.generate(14, (k) => '${500 + k}').join(','),
      });
    }
    expect(await c.post(ecg.type, ecg.records, from: ecg.from, to: ecg.to, count: ecg.count), isTrue);

    expect(seen.length, 4);
    for (final r in seen) {
      expect(r['method'], 'POST');
      final h = r['headers'] as Map<String, String>;
      expect(h['content-type'], 'application/x-www-form-urlencoded; charset=UTF-8');
      expect(jsonDecode(r['body'] as String), isA<List>()); // body is JSON, whatever the content type says
    }
    // print what a server sees (copied into the guide)
    for (final r in seen) {
      final body = r['body'] as String;
      // ignore: avoid_print
      print('${r['method']} ${r['uri']}\n${(r['headers'] as Map).entries.where((e) => ['content-type', 'accept', 'origin', 'referer', 'x-requested-with', 'user-agent', 'content-length'].contains(e.key)).map((e) => '  ${e.key}: ${e.value}').join('\n')}\n  body: ${body.length > 330 ? '${body.substring(0, 330)}... (${body.length} bytes)' : body}\n');
    }
  });
}
