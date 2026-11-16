import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/analysis.dart';
import 'package:spacemedx/core/local_store.dart';
import 'package:spacemedx/core/recorder.dart';
import 'package:spacemedx/screens/data_screen.dart';
import 'package:spacemedx/theme/app_theme.dart';
import 'package:spacemedx/widgets/range_chart.dart';

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
