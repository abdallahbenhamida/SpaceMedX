import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/analysis.dart';
import 'package:spacemedx/core/server_client.dart';
import 'package:spacemedx/core/settings.dart';
import 'package:spacemedx/screens/setup_wizard.dart';
import 'package:spacemedx/theme/app_theme.dart';
import 'package:spacemedx/widgets/range_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.update(
        serverUrl: '', userId: '', language: 'en', setupDone: false, sendToServer: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupWizard())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('first setup is a list of steps', () {
    testWidgets('shows 1/3 ... 3/3, the server step can be skipped, the server stays empty', (tester) async {
      await open(tester);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Welcome to SpaceMedX'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget); // server (optional)
      expect(find.text('Server (optional)'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.setupDone, isTrue);
      // no server: the app works on the phone alone
      expect(AppSettings.instance.serverConfigured, isFalse);
      expect(AppSettings.instance.sending, isFalse);
      expect(await ServerClient().post('pulsebelt', [
        {'a': 1}
      ]), isTrue); // nothing sent, no error
    });

    testWidgets('Back goes back, and "Skip setup" ends it at once', (tester) async {
      await open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
      await tester.tap(find.text('Skip setup'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(AppSettings.instance.setupDone, isTrue);
    });

    testWidgets('the language step changes the language at once', (tester) async {
      await open(tester);
      await tester.tap(find.text('Magyar'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.language, 'hu');
      expect(find.text('Tovább'), findsOneWidget); // "Next"
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('a server can be entered in its step', (tester) async {
      await open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'my.server.org/save');
      await tester.enterText(find.byType(TextField).last, '42');
      await tester.pump();
      expect(AppSettings.instance.serverConfigured, isTrue);
      expect(AppSettings.instance.sending, isTrue);
    });
  });

  group('the chart colours show which values are in which range', () {
    test('a line crossing the borders is cut into pieces of the right colour', () {
      // 55 (attention) -> 105 (attention) passes through the normal range 60..100
      final pieces = splitSegment(Ranges.heartRate, 55, 105);
      expect(pieces.map((p) => p.level).toList(), [Level.attention, Level.normal, Level.attention]);
      expect(pieces.first.t0, 0);
      expect(pieces.last.t1, 1);
      // the cuts are exactly at 60 and 100
      expect(pieces[0].v1, closeTo(60, 1e-9));
      expect(pieces[1].v1, closeTo(100, 1e-9));
    });

    test('a line inside one range stays one piece; a falling line works too', () {
      expect(splitSegment(Ranges.heartRate, 70, 80).length, 1);
      final down = splitSegment(Ranges.heartRate, 130, 70);
      expect(down.map((p) => p.level).toList(), [Level.abnormal, Level.attention, Level.normal]);
    });

    test('colours: normal green, abnormal orange, urgent red', () {
      expect(levelColor(Level.normal), SpaceColors.go);
      expect(levelColor(Level.urgent), SpaceColors.stop);
      expect(levelColor(Level.abnormal), isNot(levelColor(Level.normal)));
    });

    testWidgets('the chart draws with a colour key', (tester) async {
      final now = DateTime.now();
      final pts = [
        for (var i = 0; i < 10; i++) Point(now.subtract(Duration(minutes: 10 - i)), 55.0 + i * 6),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: RangeChart(
              def: Ranges.heartRate, points: pts, from: now.subtract(const Duration(minutes: 12)), to: now),
        ),
      ));
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Abnormal'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
