import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacemedx/core/server_client.dart';
import 'package:spacemedx/core/session.dart';
import 'package:spacemedx/core/settings.dart';
import 'package:spacemedx/core/sources.dart';
import 'package:spacemedx/screens/home_screen.dart';
import 'package:spacemedx/theme/app_theme.dart';

class FakeSource extends DataSource {
  FakeSource(this.problem);
  final bool problem;
  bool started = false;
  bool stopped = false;
  @override
  String get id => 'fake';
  @override
  String get name => 'Fake sensor';
  @override
  IconData get icon => Icons.sensors;
  @override
  Future<void> start() async {
    started = true;
    set(problem ? SourcePhase.problem : SourcePhase.running, problem ? 'Broken' : 'Receiving data');
  }

  @override
  Future<void> stop() async {
    stopped = true;
    set(SourcePhase.idle, 'Stopped');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('session starts and stops the sources', () async {
    await AppSettings.instance.update(serverUrl: 'https://x.test/save/', userId: '1');
    final fake = FakeSource(false);
    final session = MonitorSession(sourceFactory: (_) => [fake], useAwakeChannel: false);
    expect(session.state, SessionState.stopped);
    await session.start();
    expect(fake.started, isTrue);
    expect(session.isRunning, isTrue);
    expect(session.state, SessionState.running);
    await session.stop();
    expect(fake.stopped, isTrue);
    expect(session.state, SessionState.stopped);
  });

  test('a failing source puts the session in "attention"', () async {
    await AppSettings.instance.update(serverUrl: 'https://x.test/save/', userId: '1');
    final session = MonitorSession(sourceFactory: (_) => [FakeSource(true)], useAwakeChannel: false);
    await session.start();
    expect(session.state, SessionState.attention);
    await session.stop();
  });

  test('the server is optional: START works without a server address', () async {
    await AppSettings.instance.update(serverUrl: '', userId: '');
    final session = MonitorSession(sourceFactory: (_) => [FakeSource(false)], useAwakeChannel: false);
    expect(session.cannotStartReason, isNull);
    await session.start();
    expect(session.isRunning, isTrue);
    await session.stop();
  });

  test('cannot start without a sensor or the watch', () async {
    final session = MonitorSession(sourceFactory: (_) => [], useAwakeChannel: false);
    expect(session.cannotStartReason, isNotNull);
    await session.start();
    expect(session.isRunning, isFalse);
  });

  test('a server problem is not a sensor problem: no "attention" state', () async {
    await AppSettings.instance.update(serverUrl: 'https://x.test/save/', userId: '1');
    final server = ServerClient();
    final session = MonitorSession(server: server, sourceFactory: (_) => [FakeSource(false)], useAwakeChannel: false);
    await session.start();
    server.stats.value = server.stats.value.copy(errorKey: 'The server cannot be reached. Data is kept on the phone.');
    expect(server.stats.value.lastError, isNotNull);
    expect(session.state, SessionState.running);
    await session.stop();
  });

  testWidgets('home screen: START turns into STOP', (tester) async {
    await AppSettings.instance.update(serverUrl: 'https://x.test/save/', userId: '1', sensor: 'demo', setupDone: true);
    ServerClient.instance.resetStats();
    final session = MonitorSession(sourceFactory: (_) => [FakeSource(false)], useAwakeChannel: false);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeScreen(session: session)));
    await tester.pump();
    expect(find.text('START'), findsOneWidget);
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('STOP'), findsOneWidget);
    expect(find.text('Collecting data'), findsOneWidget);
    await tester.tap(find.text('STOP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('START'), findsOneWidget);
    // stop the timers of the session
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home screen: everything fits without scrolling, server problem stays small', (tester) async {
    await AppSettings.instance.update(serverUrl: 'https://x.test/save/', userId: '1', sensor: 'demo', setupDone: true);
    ServerClient.instance.resetStats();
    ServerClient.instance.stats.value = ServerClient.instance.stats.value
        .copy(errorKey: 'The server cannot be reached. Data is kept on the phone.');
    final session = MonitorSession(sourceFactory: (_) => [FakeSource(false)], useAwakeChannel: false);
    for (final size in const [Size(360, 640), Size(411, 891), Size(320, 568)]) {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2.0;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeScreen(session: session)));
      await tester.pump();
      // the button, the chart area and the alerts are all there at once ...
      expect(find.text('START'), findsOneWidget);
      expect(find.text('No health alerts'), findsOneWidget);
      expect(find.text('The chart appears when data arrives.'), findsOneWidget);
      // ... nothing scrolls, nothing overflows
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
      // a server problem is a small line at the bottom, not a health warning
      expect(find.text('The server cannot be reached. Data is kept on the phone.'), findsOneWidget);
      expect(find.text('Check the sensor'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    ServerClient.instance.stats.value = const UploadStats();
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('home screen: a sensor problem says "Check the sensor", not a health alert', (tester) async {
    await AppSettings.instance.update(sensor: 'demo', setupDone: true);
    ServerClient.instance.resetStats();
    final session = MonitorSession(sourceFactory: (_) => [FakeSource(true)], useAwakeChannel: false);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeScreen(session: session)));
    await tester.pump();
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Check the sensor'), findsOneWidget);
    expect(find.text('No health alerts'), findsOneWidget); // the health area stays calm
    await session.stop();
    await tester.pumpWidget(const SizedBox());
  });
}
