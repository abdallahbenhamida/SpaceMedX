import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/analysis.dart';
import 'package:spacemedx/core/local_store.dart';
import 'package:spacemedx/core/recorder.dart';
import 'package:spacemedx/core/server_client.dart';
import 'package:spacemedx/core/settings.dart';
import 'package:spacemedx/screens/data_screen.dart';
import 'package:spacemedx/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('blood pressure categories (Hungarian Hypertension Society / ESH)', () {
    ({Level level, String label}) bp(double s, double d) => Ranges.bloodPressure(s, d);

    test('optimal and normal are normal', () {
      expect(bp(118, 76).level, Level.normal);
      expect(bp(118, 76).label, 'Optimal');
      expect(bp(125, 82).level, Level.normal);
    });
    test('high-normal needs attention', () {
      expect(bp(135, 80).level, Level.attention);
      expect(bp(125, 87).level, Level.attention);
    });
    test('hypertension grades are abnormal, grade 3 is urgent', () {
      expect(bp(145, 85).level, Level.abnormal);
      expect(bp(145, 85).label, 'Grade 1 hypertension');
      expect(bp(165, 95).label, 'Grade 2 hypertension');
      expect(bp(185, 100).level, Level.urgent);
      expect(bp(130, 112).level, Level.urgent); // the worse number counts
    });
    test('boundaries belong to the higher band', () {
      expect(Ranges.systolic.levelOf(120), Level.normal);
      expect(Ranges.systolic.levelOf(130), Level.attention);
      expect(Ranges.systolic.levelOf(140), Level.abnormal);
      expect(Ranges.diastolic.levelOf(90), Level.abnormal);
    });
    test('low pressure is flagged', () {
      expect(bp(85, 55).level, Level.attention);
      expect(bp(75, 70).level, Level.abnormal);
    });
  });

  group('other ranges', () {
    test('heart rate', () {
      expect(Ranges.heartRate.levelOf(72), Level.normal);
      expect(Ranges.heartRate.levelOf(110), Level.attention);
      expect(Ranges.heartRate.levelOf(130), Level.abnormal);
      expect(Ranges.heartRate.levelOf(35), Level.urgent);
    });
    test('glucose', () {
      expect(Ranges.glucose.levelOf(5.0), Level.normal);
      expect(Ranges.glucose.levelOf(6.2), Level.attention);
      expect(Ranges.glucose.levelOf(8.0), Level.abnormal);
      expect(Ranges.glucose.levelOf(2.5), Level.urgent);
    });
    test('normal span for the chart', () {
      expect(Ranges.heartRate.normalSpan, (60.0, 100.0));
      expect(Ranges.systolic.normalSpan, (90.0, 130.0));
    });
    test('unknown is not normal', () {
      expect(Level.unknown.rank, lessThan(Level.normal.rank));
      expect(SeriesSummary.of(Ranges.heartRate, const []).lastLevel, Level.unknown);
    });
  });

  group('SeriesSummary', () {
    List<Point> pts(List<double> v) {
      final t = DateTime(2026, 1, 1);
      return [for (var i = 0; i < v.length; i++) Point(t.add(Duration(minutes: i * 10)), v[i])];
    }

    test('statistics and share in the normal range', () {
      final s = SeriesSummary.of(Ranges.heartRate, pts([70, 72, 74, 130, 71, 73]));
      expect(s.count, 6);
      expect(s.min, 70);
      expect(s.max, 130);
      expect(s.alertCount, 1);
      expect(s.normalShare, closeTo(5 / 6, 1e-9));
      expect(s.lastLevel, Level.normal);
    });
    test('trend needs enough points', () {
      expect(SeriesSummary.of(Ranges.heartRate, pts([70, 90])).trend, Trend.unknown);
      expect(SeriesSummary.of(Ranges.heartRate, pts([60, 65, 70, 80, 90, 100])).trend, Trend.rising);
      expect(SeriesSummary.of(Ranges.heartRate, pts([100, 90, 80, 70, 65, 60])).trend, Trend.falling);
      expect(SeriesSummary.of(Ranges.heartRate, pts([70, 71, 70, 72, 70, 71])).trend, Trend.steady);
    });
  });

  group('MemoryStore', () {
    test('returns raw points when few, buckets when many', () async {
      final st = MemoryStore();
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 1000; i++) {
        await st.addObservation('hr', t0.add(Duration(seconds: i)), 60.0 + (i % 10), 'x');
      }
      final all = await st.series('hr', t0, t0.add(const Duration(seconds: 1000)), maxPoints: 100);
      expect(all.length, lessThanOrEqualTo(101));
      expect(all.first.min, isNotNull);
      final few = await st.series('hr', t0, t0.add(const Duration(seconds: 3)), maxPoints: 100);
      expect(few.length, 4);
      await st.purgeOlderThan(t0.add(const Duration(seconds: 500)));
      expect(await st.observationCount(), 500);
    });
  });

  group('Recorder alerts', () {
    Recorder make() => Recorder(store: MemoryStore(), haptics: false);

    test('a single abnormal heart rate does not alert, a sustained one does', () async {
      final r = make();
      for (var i = 0; i < Recorder.sustainedSamples - 1; i++) {
        await r.record('hr', 140);
      }
      expect(r.alerts, isEmpty);
      await r.record('hr', 140);
      expect(r.alerts.length, 1);
      expect(r.alerts.first.level, Level.abnormal);
      // the same state does not alert again at once
      await r.record('hr', 141);
      expect(r.alerts.length, 1);
    });

    test('a normal value resets the streak', () async {
      final r = make();
      for (var i = 0; i < Recorder.sustainedSamples - 1; i++) {
        await r.record('hr', 140);
      }
      await r.record('hr', 70);
      await r.record('hr', 140);
      expect(r.alerts, isEmpty);
    });

    test('a high blood pressure alerts at once, normal does not', () async {
      final r = make();
      await r.recordBloodPressure(118, 76);
      expect(r.alerts, isEmpty);
      await r.recordBloodPressure(150, 95);
      expect(r.alerts.single.title, 'Blood pressure');
      expect(r.latest['sys']!.value, 150);
    });

    test('values are stored for the charts', () async {
      final r = make();
      await r.record('hr', 80);
      await r.recordBloodPressure(120, 80);
      final now = DateTime.now();
      final s = await r.store.series('sys', now.subtract(const Duration(minutes: 1)), now.add(const Duration(minutes: 1)));
      expect(s.single.value, 120);
    });
  });

  group('ServerClient queue survives a restart', () {
    test('waiting batches are restored from the store and delivered', () async {
      final store = MemoryStore();
      var status = 503;
      http.Client client() => MockClient((r) async => http.Response('', status));
      final a = ServerClient(client: client(), store: store)
        ..baseOverride = (() => 'https://s.test/save/')
        ..userOverride = (() => '7')
        ..sendEnabledOverride = (() => true);
      await a.post('pulsebelt', [{'timestamp': 1, 'pulse': '70'}]);
      await pumpEventQueue();
      expect((await store.queue()).length, 1);

      // "restart": a new client with the same store
      status = 200;
      final b = ServerClient(client: client(), store: store)
        ..baseOverride = (() => 'https://s.test/save/')
        ..userOverride = (() => '7')
        ..sendEnabledOverride = (() => true);
      await b.restore();
      expect(b.stats.value.waiting, 1);
      await b.flushQueue();
      expect(b.stats.value.waiting, 0);
      expect(b.stats.value.sent, 1);
      expect(await store.queue(), isEmpty);
    });

    test('"store on this phone only" sends nothing', () async {
      var calls = 0;
      final c = ServerClient(client: MockClient((r) async {
        calls++;
        return http.Response('', 200);
      }))
        ..baseOverride = (() => 'https://s.test/save/')
        ..userOverride = (() => '7')
        ..sendEnabledOverride = (() => false);
      expect(await c.post('pulsebelt', [{'a': 1}]), isTrue);
      expect(calls, 0);
    });
  });

  testWidgets('Data screen draws charts with data and without', (tester) async {
    final rec = Recorder(store: MemoryStore(), haptics: false);
    await AppSettings.instance.update(glucoseUnit: 'mgdl');
    final now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      await rec.record('hr', 65.0 + i % 8, time: now.subtract(Duration(minutes: 30 - i)));
    }
    await rec.recordBloodPressure(128, 82, time: now.subtract(const Duration(minutes: 5)));
    await rec.record('glu', 6.1, time: now.subtract(const Duration(minutes: 3)));
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: DataScreen(recorder: rec)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('Blood pressure'), findsWidgets);
    expect(find.text('128/82'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await AppSettings.instance.update(glucoseUnit: 'mmol');
  });
}
