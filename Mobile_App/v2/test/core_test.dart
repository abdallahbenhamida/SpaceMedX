import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spacemedx/core/server_client.dart';
import 'package:spacemedx/core/settings.dart';

void main() {
  group('AppSettings.normalizeBase', () {
    test('adds scheme and trailing slash', () {
      expect(AppSettings.normalizeBase('my.server.org/save'), 'https://my.server.org/save/');
      expect(AppSettings.normalizeBase(' http://10.0.0.5:8000/save/ '), 'http://10.0.0.5:8000/save/');
      expect(AppSettings.normalizeBase(''), '');
    });
  });

  group('ServerClient', () {
    late List<http.Request> requests;
    ServerClient make(int Function() status) {
      requests = [];
      return ServerClient(
        client: MockClient((r) async {
          requests.add(r);
          return http.Response('', status());
        }),
      )
        ..baseOverride = (() => 'https://srv.test/save/')
        ..userOverride = (() => '42');
    }

    test('posts to the documented URL scheme with a JSON body', () async {
      final c = make(() => 200);
      final ok = await c.post('pulsebelt', [
        {'timestamp': 1000, 'pulse': '70'}
      ], from: 1000, to: 1000);
      expect(ok, isTrue);
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://srv.test/save/42/pulsebelt/1/1000/1000?profil=0&deviceid=0&ext=1');
      expect(r.headers['Content-Type'] ?? r.headers['content-type'], contains('application/x-www-form-urlencoded'));
      expect(jsonDecode(r.body), [
        {'timestamp': 1000, 'pulse': '70'}
      ]);
      expect(c.stats.value.sent, 1);
      expect(c.stats.value.lastError, isNull);
    });

    test('keeps data when the server is down and delivers it later', () async {
      var status = 503;
      final c = make(() => status);
      expect(await c.post('pulsebelt', [{'timestamp': 1, 'pulse': '60'}]), isFalse);
      expect(c.stats.value.waiting, 1);
      expect(c.stats.value.lastError, isNotNull);
      status = 200;
      await c.flushQueue();
      expect(c.stats.value.waiting, 0);
      expect(c.stats.value.sent, 1);
    });

    test('drops data the server refuses for good (4xx)', () async {
      final c = make(() => 404);
      expect(await c.post('pulsebelt', [{'timestamp': 1}]), isFalse);
      expect(c.stats.value.waiting, 0);
      expect(c.stats.value.lastError, contains('404'));
    });

    test('without a server address the data just stays on the phone: no request, no error', () async {
      var calls = 0;
      final c = ServerClient(client: MockClient((r) async {
        calls++;
        return http.Response('', 200);
      }))
        ..baseOverride = (() => '')
        ..userOverride = (() => '');
      expect(await c.post('x', [{'a': 1}]), isTrue);
      expect(calls, 0);
      expect(c.stats.value.lastError, isNull);
      expect(c.stats.value.waiting, 0);
    });
  });
}
