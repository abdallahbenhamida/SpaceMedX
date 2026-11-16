import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

    // heart rate, as the demo sensor sends it (batched like the app does)
    expect(
        await c.post('pulsebelt', [
          {'pulse': '72', 'timestamp': 1790000000000, 'device': 'DEMO', 'deviceid': 'pulsebelt', 'remark': 'simulated'}
        ]),
        isTrue);

    // the record types a real blood pressure monitor, glucose meter and ECG recorder would send
    // (no source of them is built into this version; the server accepts them)
    expect(
        await c.post('bloodpressure', [
          {
            'systole': 121,
            'diastole': 79,
            'pulse': 66,
            'daqtimestamp': 1790000000000,
            'meatimestamp': '2026/11/14 8:30:00',
            'timestamp': 1790000000000,
            'description': 'at rest',
            'device': 'EID_102',
            'deviceid': 'bloodpressure',
          }
        ], from: 1790000000000, to: 1790000000000),
        isTrue);
    expect(
        await c.post('bloodsugar', [
          {
            'glucose_level': 5.4,
            'glucose_level_unit': 'mmol/L',
            'daqtimestamp': 1790000000000,
            'meatimestamp': '2026.11.14. 8:31',
            'timestamp': 1790000000000,
          }
        ], from: 1790000000000, to: 1790000000000),
        isTrue);
    expect(
        await c.post('ecg', [
          for (var i = 0; i < 4; i++) {'timestamp': 1790000000000 + i * 8, 'ch0': '${500 + i}'}
        ], from: 1790000000000, to: 1790000000024, count: 4),
        isTrue);

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
