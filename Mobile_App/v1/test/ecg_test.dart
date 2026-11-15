import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/device_records.dart';
import 'package:spacemedx/core/local_store.dart';
import 'package:spacemedx/core/recorder.dart';
import 'package:spacemedx/theme/app_theme.dart';
import 'package:spacemedx/widgets/ecg_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ecgSamples parses a Savvy packet string and raw lists', () {
    expect(DeviceRecords.ecgSamples('500,501,502'), [500.0, 501.0, 502.0]);
    expect(DeviceRecords.ecgSamples([1, 2, 3]), [1.0, 2.0, 3.0]);
    expect(DeviceRecords.ecgSamples(''), isEmpty);
    expect(DeviceRecords.ecgSamples(null), isEmpty);
    expect(DeviceRecords.ecgSamples('1,x,3'), [1.0, 3.0]);
  });

  test('the live buffer keeps only the newest 10 seconds and ticks', () {
    final r = Recorder(store: MemoryStore(), haptics: false);
    var ticks = 0;
    r.ecgTick.addListener(() => ticks++);
    final cap = Recorder.ecgSampleRate * Recorder.ecgKeepSeconds;
    for (var i = 0; i < 200; i++) {
      r.addEcgSamples(List.generate(14, (k) => (i * 14 + k).toDouble()));
    }
    expect(ticks, 200);
    expect(r.ecg.length, cap);
    expect(r.ecg.last, 200 * 14 - 1); // newest last
    expect(r.ecg.first, 200 * 14 - cap);
    r.resetLive();
    expect(r.ecg, isEmpty);
  });

  testWidgets('the ECG card draws without data, with data, and keeps repainting', (tester) async {
    final r = Recorder(store: MemoryStore(), haptics: false);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: EcgCard(recorder: r))));
    await tester.pump();
    expect(find.text('ECG, live'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      r.addEcgSamples(List.generate(14, (k) => 500.0 + 80 * (((i * 14 + k) % 100) / 100)));
      await tester.pump(const Duration(milliseconds: 112));
    }
    expect(tester.takeException(), isNull);
    // signal stops: the chart must still repaint (timer) without errors
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
