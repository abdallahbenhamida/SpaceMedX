import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/analysis.dart';
import 'package:spacemedx/core/iss_env.dart';
import 'package:spacemedx/core/local_store.dart';
import 'package:spacemedx/core/recorder.dart';
import 'package:spacemedx/core/settings.dart';
import 'package:spacemedx/l10n/l10n.dart';
import 'package:spacemedx/ml/ecg_anomaly_model.dart';
import 'package:spacemedx/ml/iss_env_model.dart';
import 'package:spacemedx/ml/vitals_model.dart';
import 'package:spacemedx/theme/app_theme.dart';
import 'package:spacemedx/widgets/iss_strip.dart';

String _asset() => File('assets/data/iss_env_sample.json').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.update(language: 'en', alertsOn: true, vibrate: false);
  });

  group('the models in lib/ml (stand-ins or trained: the rules below hold for both)', () {
    test('ISS bands give the five colours in order', () {
      final b = IssEnvModel.co2Bands;
      expect(b.length, 4);
      expect(b, orderedEquals([...b]..sort()));
      expect(IssEnvModel.levelOf(IssVar.co2, b[0] - 1), IssLevel.veryLow);
      expect(IssEnvModel.levelOf(IssVar.co2, (b[0] + b[1]) / 2), IssLevel.low);
      expect(IssEnvModel.levelOf(IssVar.co2, (b[1] + b[2]) / 2), IssLevel.normal);
      expect(IssEnvModel.levelOf(IssVar.co2, (b[2] + b[3]) / 2), IssLevel.high);
      expect(IssEnvModel.levelOf(IssVar.co2, b[3] + 1), IssLevel.veryHigh);
      for (final v in IssVar.values) {
        expect(IssEnvModel.bandsOf(v).length, 4, reason: '$v');
      }
    });

    test('a steady heart rate raises no alert, an erratic one does', () {
      final m = VitalsMonitor(VitalSignal.heartRate);
      for (var i = 0; i < 60; i++) {
        expect(m.addMinute(70.0 + (i % 3))?.alert ?? false, isFalse, reason: 'minute $i');
      }
      var alerted = false;
      for (final v in <double>[135, 70, 135, 70, 135, 70, 135]) {
        alerted = (m.addMinute(v)?.alert ?? false) || alerted;
      }
      expect(alerted, isTrue);
    });

    test('an implausible value (a sensor artefact) is ignored', () {
      final m = VitalsMonitor(VitalSignal.temperature);
      expect(m.addMinute(5.0), isNull);
      expect(m.addMinute(double.nan), isNull);
    });

    test('the ECG model gives no answer (and never an alert) while it is not trained', () {
      if (EcgAnomalyModel.trained) return; // a trained model has its own generated test
      expect(EcgAnomalyModel.predict(List<double>.filled(EcgAnomalyModel.windowSamples, 500)), isNull);
      final ds = EcgAnomalyMonitor().addSamples(List<double>.filled(EcgAnomalyModel.windowSamples * 2, 500));
      expect(ds.every((d) => !d.alert), isTrue);
    });

    test('the ECG monitor emits one decision per stride', () {
      final m = EcgAnomalyMonitor();
      expect(m.addSamples(List<double>.filled(EcgAnomalyModel.windowSamples - 1, 512)), isEmpty);
      expect(m.addSamples([512.0]).length, 1);
      expect(m.addSamples(List<double>.filled(EcgAnomalyModel.strideSamples, 512)).length, 1);
    });
  });

  group('the ISS replay of the real NASA recording', () {
    test('loads 48 hours and every sample is judged', () {
      final p = IssEnvPlayer()..loadFromJson(_asset());
      addTearDown(p.dispose);
      expect(p.ready, isTrue);
      expect(p.mission, 'RR-12');
      expect(p.assessments.map((a) => a.variable), containsAll(IssVar.values));
      final rad = p.assessments.firstWhere((a) => a.variable == IssVar.radiation);
      expect(rad.value, closeTo(0.35, 0.06)); // mGy/day on 12 May 2019
    });

    test('it steps through all the samples, then starts again, and every value stays in 5 colours', () {
      final p = IssEnvPlayer()..loadFromJson(_asset());
      addTearDown(p.dispose);
      final seen = <IssLevel>{};
      final times = <DateTime>[];
      for (var i = 0; i < 200; i++) {
        p.step();
        for (final a in p.assessments) {
          seen.add(a.level);
        }
        times.add(p.sampleTime!);
      }
      expect(seen, contains(IssLevel.normal));
      expect(seen.length, greaterThanOrEqualTo(3));
      // time goes forward by 30 minutes and restarts at the end of the recording
      expect(times.where((t) => t == times.first).length, greaterThan(1));
    });

    test('the humidity jump in the recording (41% to 60% in an hour) is flagged as a jump', () {
      if (IssEnvModel.trained) return; // a trained network may forecast it differently
      final p = IssEnvPlayer()..loadFromJson(_asset());
      addTearDown(p.dispose);
      var jumped = false;
      for (var i = 0; i < 96; i++) {
        p.step();
        final rh = p.assessments.firstWhere((a) => a.variable == IssVar.humidity);
        if (rh.jump) jumped = true;
      }
      expect(jumped, isTrue);
    });

    test('a broken file does not crash the player', () {
      final p = IssEnvPlayer();
      addTearDown(p.dispose);
      expect(() => p.loadFromJson('not json'), throwsA(anything)); // load() catches this
      expect(p.ready, isFalse);
    });
  });

  testWidgets('the ISS strip shows the four values in their colours, and the details open on a tap', (tester) async {
    final p = IssEnvPlayer()..loadFromJson(_asset());
    addTearDown(p.dispose);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: SizedBox(height: 70, child: IssStrip(player: p))))));
    await tester.pump();
    expect(find.text('ISS'), findsOneWidget);
    expect(find.text('ppm'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    expect(find.text('mGy/day'), findsOneWidget);
    await tester.tap(find.text('ISS'));
    await tester.pumpAndSettle();
    expect(find.text('ISS environment'), findsOneWidget);
    expect(find.text('Carbon dioxide'), findsOneWidget);
    expect(find.textContaining('Usual range'), findsWidgets);
    expect(find.textContaining('not a safety limit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('the five colours are blue, light blue, green, yellow and red', () {
    expect(issColor(IssLevel.veryLow), const Color(0xFF3B6FFF));
    expect(issColor(IssLevel.low), const Color(0xFF7FD4FF));
    expect(issColor(IssLevel.normal), SpaceColors.go);
    expect(issColor(IssLevel.high), const Color(0xFFFFD23F));
    expect(issColor(IssLevel.veryHigh), SpaceColors.stop);
    L10n.apply('hu', 'en');
    expect(issLevelText(IssLevel.normal), 'Normál');
    L10n.apply('en', 'en');
  });

  group('the recorder feeds the models', () {
    test('a sudden heart rate change raises an alert; a steady rate does not', () async {
      final r = Recorder(store: MemoryStore(), haptics: false);
      final t0 = DateTime(2026, 11, 15, 10, 0);
      for (var i = 0; i < 50; i++) {
        for (var s = 0; s < 3; s++) {
          await r.record('hr', 70.0 + (i % 3), time: t0.add(Duration(minutes: i, seconds: s * 15)));
        }
      }
      expect(r.alerts.where((a) => a.paramId == 'v_hr'), isEmpty);
      var m = 50;
      for (final v in <double>[135, 70, 135, 70, 135, 70, 135]) {
        await r.record('hr', v, time: t0.add(Duration(minutes: m++)));
      }
      final alerts = r.alerts.where((a) => a.paramId == 'v_hr').toList();
      expect(alerts, isNotEmpty);
      expect(alerts.first.titleText, 'Unusual heart rate change');
      expect(alerts.first.detailText, contains('bpm'));
      expect(alerts.first.detailText, contains('Changed faster than expected'));
    });

    test('temperature is a data type the app knows; a jump in it raises an alert', () async {
      final r = Recorder(store: MemoryStore(), haptics: false);
      expect(r.defs.containsKey('temp'), isTrue);
      final t0 = DateTime(2026, 11, 15, 10, 0);
      for (var i = 0; i < 50; i++) {
        await r.record('temp', 33.4 + 0.05 * (i % 2), time: t0.add(Duration(minutes: i)));
      }
      var m = 50;
      for (final v in <double>[35.8, 33.4, 35.8, 33.4, 35.8, 33.4, 35.8, 33.4]) {
        await r.record('temp', v, time: t0.add(Duration(minutes: m++)));
      }
      expect(r.alerts.where((a) => a.paramId == 'v_temp'), isNotEmpty);
      expect((await r.store.paramsWithData(t0.subtract(const Duration(hours: 1)), t0.add(const Duration(hours: 3)))), contains('temp'));
    });

    test('a gap of more than two minutes starts the model again (no false alert after a pause)', () async {
      final r = Recorder(store: MemoryStore(), haptics: false);
      final t0 = DateTime(2026, 11, 15, 10, 0);
      for (var i = 0; i < 45; i++) {
        await r.record('hr', 70.0, time: t0.add(Duration(minutes: i)));
      }
      // the watch was off for an hour, then a different (high) rate: not a "sudden change"
      for (var i = 0; i < 10; i++) {
        await r.record('hr', 120.0, time: t0.add(Duration(minutes: 120 + i)));
      }
      expect(r.alerts.where((a) => a.paramId == 'v_hr'), isEmpty);
    });

    test('ECG samples go to the ECG model; a stand-in never alerts', () {
      final r = Recorder(store: MemoryStore(), haptics: false);
      r.addEcgSamples(List<double>.filled(EcgAnomalyModel.windowSamples * 2, 500));
      if (!EcgAnomalyModel.trained) expect(r.alerts.where((a) => a.paramId == 'ecg'), isEmpty);
      expect(r.ecg.length, EcgAnomalyModel.windowSamples * 2);
    });
  });

  test('the alert texts are translated', () {
    final a = HealthAlert(DateTime(2026), 'v_hr', Level.attention, 'Unusual heart rate change', 'x',
        value: '120 bpm', label: 'Changed faster than expected');
    L10n.apply('hu', 'en');
    expect(a.titleText, 'Szokatlan pulzusváltozás');
    expect(a.detailText, '120 bpm: A vártnál gyorsabban változott');
    L10n.apply('en', 'en');
  });
}
