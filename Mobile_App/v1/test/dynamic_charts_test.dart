import 'package:e77hal_plugin/e77hal_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/analysis.dart';
import 'package:spacemedx/core/local_store.dart';
import 'package:spacemedx/core/recorder.dart';
import 'package:spacemedx/core/sources.dart';
import 'package:spacemedx/screens/data_screen.dart';
import 'package:spacemedx/theme/app_theme.dart';
import 'package:spacemedx/watch/watch_link.dart';
import 'package:spacemedx/watch/watch_protocol.dart';
import 'package:spacemedx/widgets/range_chart.dart';

class _NoTransport implements BleTransport {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WatchSource source(Recorder r) => WatchSource(link: WatchLink(transport: _NoTransport()), recorder: r);

WatchParam param(String id, String name, List<String> fields, {double hz = 1, String unit = ''}) => WatchParam(
      id: id,
      name: name,
      unit: unit,
      group: 'x',
      available: true,
      why: '',
      fields: fields,
      rateHz: hz,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> show(WidgetTester tester, Recorder r) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: DataScreen(recorder: r)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('no data: no chart at all, a short message', (tester) async {
    final r = Recorder(store: MemoryStore(), haptics: false);
    await show(tester, r);
    expect(find.byType(RangeChart), findsNothing);
    expect(find.text('No data yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one data type gives exactly one chart', (tester) async {
    final r = Recorder(store: MemoryStore(), haptics: false);
    final now = DateTime.now();
    for (var i = 0; i < 12; i++) {
      await r.record('hr', 70.0 + i % 5, time: now.subtract(Duration(minutes: 12 - i)));
    }
    await show(tester, r);
    expect(find.byType(RangeChart), findsOneWidget);
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('Blood pressure'), findsNothing);
    expect(find.text('Blood glucose'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blood pressure and glucose appear only when received', (tester) async {
    final r = Recorder(store: MemoryStore(), haptics: false);
    await r.recordBloodPressure(120, 80, time: DateTime.now().subtract(const Duration(minutes: 2)));
    await show(tester, r);
    // systolic + diastolic charts of the one blood pressure card
    expect(find.text('Blood pressure'), findsWidgets);
    expect(find.text('Heart rate'), findsNothing);
    expect(find.text('Blood glucose'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a watch with many data types gives many charts, without ranges for the unknown ones', (tester) async {
    final r = Recorder(store: MemoryStore(), haptics: false);
    final w = source(r);
    final t0 = DateTime.now().millisecondsSinceEpoch - 60000;
    WatchFrame frame(String id, int n, int step, List<double?> Function(int) v) =>
        WatchFrame(id, [for (var i = 0; i < n; i++) WatchSample(t0 + i * step, v(i))]);

    w.handleFrame(param('hr', 'Heart rate', ['bpm'], unit: 'bpm'), frame('hr', 20, 1000, (i) => [70.0 + i % 4]));
    w.handleFrame(param('steps', 'Steps', ['steps'], unit: 'steps'), frame('steps', 20, 1000, (i) => [100.0 + i]));
    w.handleFrame(
        param('acc', 'Accelerometer', ['x', 'y', 'z'], hz: 50, unit: 'm/s2'),
        frame('acc', 100, 20, (i) => [0.1 * i, 9.8, 0.0]));
    w.handleFrame(param('ecg', 'ECG', ['mv'], hz: 500), frame('ecg', 500, 2, (i) => [i * 1.0])); // not charted

    await show(tester, r);
    expect(r.defs.keys, containsAll(['w_steps', 'w_acc_x', 'w_acc_y', 'w_acc_z']));
    expect(r.defs.containsKey('w_ecg'), isFalse);
    // hr + steps + acc x/y/z = 5 charts
    expect(find.byType(RangeChart), findsNWidgets(5));
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Accelerometer x'), findsOneWidget);
    expect(find.text('No normal range is defined for this value.'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('slow data types are stored once per second', () async {
    final r = Recorder(store: MemoryStore(), haptics: false);
    final w = source(r);
    final t0 = DateTime.now().millisecondsSinceEpoch - 60000;
    w.handleFrame(param('steps', 'Steps', ['steps']),
        WatchFrame('steps', [for (var i = 0; i < 10; i++) WatchSample(t0 + i * 100, [i * 1.0])]));
    final now = DateTime.now();
    final s = await r.store.series('w_steps', now.subtract(const Duration(minutes: 5)), now);
    expect(s.length, lessThanOrEqualTo(2)); // 10 samples within one second
  });

  test('store: data types present, and their names survive a restart', () async {
    final st = MemoryStore();
    final r = Recorder(store: st, haptics: false);
    r.registerParam(const ParamDef.plain(id: 'w_steps', name: 'Steps', unit: 'steps'));
    await r.record('w_steps', 5);
    final now = DateTime.now();
    expect(await st.paramsWithData(now.subtract(const Duration(hours: 1)), now.add(const Duration(minutes: 1))), {'w_steps'});
    final r2 = Recorder(store: st, haptics: false);
    expect(r2.defs.containsKey('w_steps'), isFalse);
    await r2.loadDefs();
    expect(r2.defs['w_steps']!.name, 'Steps');
    expect(r2.defs['w_steps']!.hasRanges, isFalse);
  });

  test('a plain data type is summarised but never judged', () {
    const def = ParamDef.plain(id: 'x', name: 'X', unit: '');
    final t = DateTime(2026, 1, 1);
    final s = SeriesSummary.of(def, [for (var i = 0; i < 8; i++) Point(t.add(Duration(minutes: i)), 10.0 + i * 5)]);
    expect(s.lastLevel, Level.unknown);
    expect(s.trend, Trend.rising);
    expect(s.alertCount, 0);
  });
}
