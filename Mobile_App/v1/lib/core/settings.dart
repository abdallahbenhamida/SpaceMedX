
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Which sensor the astronaut picked (besides the watch), and how it connects.
/// All texts are English keys: show them with `tr()`.
class SensorChoice {
  const SensorChoice(
    this.id,
    this.title,
    this.subtitle, {
    this.steps = const [],
    this.needsPin = false,
  });
  final String id;
  final String title;
  final String subtitle;

  /// The connection steps in plain words.
  final List<String> steps;

  /// Needs a PIN (and the ECG channel) before it can connect.
  final bool needsPin;

  /// Something to read or enter when this sensor is chosen (shown in a pop-up).
  bool get needsPopup => needsPin || steps.isNotEmpty && id != demo.id;

  static const none = SensorChoice('none', 'No extra sensor', 'Only the watch (if switched on)');

  static const demo = SensorChoice(
    'demo',
    'Demo sensor',
    'Simulated heart rate, no hardware needed',
    steps: ['Nothing to connect. The app makes up a heart rate so you can try everything.'],
  );

  static const polar = SensorChoice(
    'EID_107',
    'Heart rate belt',
    'Polar H7',
    steps: [
      'Put the belt on (wet the electrodes) so it wakes up.',
      'Press START. The app looks for a heart rate belt nearby.',
      'The app connects and shows the heart rate.',
    ],
  );

  static const savvy = SensorChoice(
    'EID_103',
    'ECG recorder',
    'Savvy ECG, needs its PIN',
    needsPin: true,
    steps: [
      'Switch the Savvy ECG on.',
      'Enter the PIN of your recorder.',
      'Press START. The app looks for a device called "Savvy" and connects.',
      'The app sends the PIN to the recorder, then the ECG starts.',
      'If the recorder goes out of range, the phone reconnects by itself.',
    ],
  );

  static const beurer = SensorChoice(
    'EID_102',
    'Blood pressure monitor',
    'Beurer BM85',
    steps: [
      'Press START in the app first. It looks for "Beurer BM85".',
      'Then take a measurement with the monitor.',
      'The monitor sends its result and closes the connection by itself. The app takes the newest result and waits for the next one.',
    ],
  );

  static const bpGeneric = SensorChoice(
    'EID_108',
    'Other blood pressure monitor',
    'Any Bluetooth monitor with the standard profile',
    steps: [
      'Press START in the app first. It looks for any nearby blood pressure monitor that uses the standard Bluetooth profile.',
      'Then take a measurement. Some monitors must be switched to Bluetooth mode first (see their manual).',
      'The app takes the result and waits for the next one.',
      'If nothing is found, the monitor probably uses a private protocol and cannot be used.',
    ],
  );

  static const dcont = SensorChoice(
    'EID_101',
    'Glucose meter',
    'Dcont NEMERE',
    steps: [
      'Switch the meter on.',
      'Press START. The app looks for "Dcont66".',
      'Android asks to pair with the meter: confirm it (on the phone, and on the meter if it asks).',
      'The app connects and receives the glucose measurements.',
    ],
  );

  static const all = [none, demo, polar, savvy, beurer, bpGeneric, dcont];

  static SensorChoice byId(String id) => all.firstWhere((s) => s.id == id, orElse: () => none);
}

/// Everything the astronaut can configure. Stored on the phone.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // storage keys
  static const _kServer = 'serverUrl';
  static const _kUser = 'userId';
  static const _kSensor = 'sensor';
  static const _kPin = 'savvyPin';
  static const _kWatch = 'useWatch';
  static const _kSend = 'sendToServer';
  static const _kInterval = 'uploadSeconds';
  static const _kAlerts = 'alertsOn';
  static const _kVibrate = 'vibrate';
  static const _kAwake = 'keepScreenOn';
  static const _kHistory = 'historyDays';
  static const _kGlucose = 'glucoseUnit';
  static const _kChannel = 'ecgChannel';
  static const _kLanguage = 'language';
  static const _kSetupDone = 'setupDone';

  String serverUrl = '';
  String userId = '';
  String sensor = SensorChoice.demo.id;
  String savvyPin = '';
  bool useWatch = false;

  /// false = keep everything on the phone and send nothing ("offline mode").
  bool sendToServer = true;

  /// How often collected data is sent (seconds).
  int uploadSeconds = 10;

  bool alertsOn = true;
  bool vibrate = true;
  bool keepScreenOn = true;

  /// How long measurements are kept on the phone.
  int historyDays = 30;

  /// 'mmol' or 'mgdl' (display only; the server always gets the device value).
  String glucoseUnit = 'mmol';

  /// Channel of the Savvy ECG that is sent (ch0 ... ch9).
  String ecgChannel = 'ch0';

  /// 'system' (the phone's language) or a language code such as 'hu'.
  String language = 'system';

  /// The first-start steps were finished or skipped.
  bool setupDone = false;

  bool loaded = false;

  /// A server address and a user id were entered. The server is optional:
  /// without them the app works on the phone alone.
  bool get serverConfigured => normalizeBase(serverUrl).isNotEmpty && userId.trim().isNotEmpty;

  /// Data really goes to a server.
  bool get sending => sendToServer && serverConfigured;

  SensorChoice get sensorChoice => SensorChoice.byId(sensor);

  void _applyLanguage() => L10n.apply(language, PlatformDispatcher.instance.locale.languageCode);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? '';
    userId = p.getString(_kUser) ?? '';
    sensor = p.getString(_kSensor) ?? SensorChoice.demo.id;
    savvyPin = p.getString(_kPin) ?? '';
    useWatch = p.getBool(_kWatch) ?? false;
    sendToServer = p.getBool(_kSend) ?? true;
    uploadSeconds = p.getInt(_kInterval) ?? 10;
    alertsOn = p.getBool(_kAlerts) ?? true;
    vibrate = p.getBool(_kVibrate) ?? true;
    keepScreenOn = p.getBool(_kAwake) ?? true;
    historyDays = p.getInt(_kHistory) ?? 30;
    glucoseUnit = p.getString(_kGlucose) ?? 'mmol';
    ecgChannel = p.getString(_kChannel) ?? 'ch0';
    language = p.getString(_kLanguage) ?? 'system';
    // phones that already used an earlier version have finished the setup
    setupDone = p.getBool(_kSetupDone) ?? (serverUrl.isNotEmpty && userId.isNotEmpty);
    loaded = true;
    _applyLanguage();
    notifyListeners();
  }

  Future<void> update({
    String? serverUrl,
    String? userId,
    String? sensor,
    String? savvyPin,
    bool? useWatch,
    bool? sendToServer,
    int? uploadSeconds,
    bool? alertsOn,
    bool? vibrate,
    bool? keepScreenOn,
    int? historyDays,
    String? glucoseUnit,
    String? ecgChannel,
    String? language,
    bool? setupDone,
  }) async {
    if (serverUrl != null) this.serverUrl = serverUrl.trim();
    if (userId != null) this.userId = userId.trim();
    if (sensor != null) this.sensor = sensor;
    if (savvyPin != null) this.savvyPin = savvyPin.trim();
    if (useWatch != null) this.useWatch = useWatch;
    if (sendToServer != null) this.sendToServer = sendToServer;
    if (uploadSeconds != null) this.uploadSeconds = uploadSeconds;
    if (alertsOn != null) this.alertsOn = alertsOn;
    if (vibrate != null) this.vibrate = vibrate;
    if (keepScreenOn != null) this.keepScreenOn = keepScreenOn;
    if (historyDays != null) this.historyDays = historyDays;
    if (glucoseUnit != null) this.glucoseUnit = glucoseUnit;
    if (ecgChannel != null) this.ecgChannel = ecgChannel;
    if (language != null) {
      this.language = language;
      _applyLanguage();
    }
    if (setupDone != null) this.setupDone = setupDone;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, this.serverUrl);
    await p.setString(_kUser, this.userId);
    await p.setString(_kSensor, this.sensor);
    await p.setString(_kPin, this.savvyPin);
    await p.setBool(_kWatch, this.useWatch);
    await p.setBool(_kSend, this.sendToServer);
    await p.setInt(_kInterval, this.uploadSeconds);
    await p.setBool(_kAlerts, this.alertsOn);
    await p.setBool(_kVibrate, this.vibrate);
    await p.setBool(_kAwake, this.keepScreenOn);
    await p.setInt(_kHistory, this.historyDays);
    await p.setString(_kGlucose, this.glucoseUnit);
    await p.setString(_kChannel, this.ecgChannel);
    await p.setString(_kLanguage, this.language);
    await p.setBool(_kSetupDone, this.setupDone);
  }

  /// "myserver.org/api/save" -> "https://myserver.org/api/save/".
  /// Returns '' when nothing usable was typed.
  static String normalizeBase(String? value) {
    var v = (value ?? '').trim();
    if (v.isEmpty) return '';
    if (!v.contains('://')) v = 'https://$v';
    if (!v.endsWith('/')) v = '$v/';
    return v;
  }
}
