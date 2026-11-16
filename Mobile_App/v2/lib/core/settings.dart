import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Everything the astronaut can configure. Stored on the phone.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // storage keys
  static const _kServer = 'serverUrl';
  static const _kUser = 'userId';
  static const _kSend = 'sendToServer';
  static const _kInterval = 'uploadSeconds';
  static const _kAlerts = 'alertsOn';
  static const _kVibrate = 'vibrate';
  static const _kAwake = 'keepScreenOn';
  static const _kHistory = 'historyDays';
  static const _kGlucose = 'glucoseUnit';
  static const _kLanguage = 'language';
  static const _kSetupDone = 'setupDone';

  String serverUrl = '';
  String userId = '';

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

  void _applyLanguage() => L10n.apply(language, PlatformDispatcher.instance.locale.languageCode);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? '';
    userId = p.getString(_kUser) ?? '';
    sendToServer = p.getBool(_kSend) ?? true;
    uploadSeconds = p.getInt(_kInterval) ?? 10;
    alertsOn = p.getBool(_kAlerts) ?? true;
    vibrate = p.getBool(_kVibrate) ?? true;
    keepScreenOn = p.getBool(_kAwake) ?? true;
    historyDays = p.getInt(_kHistory) ?? 30;
    glucoseUnit = p.getString(_kGlucose) ?? 'mmol';
    language = p.getString(_kLanguage) ?? 'system';
    setupDone = p.getBool(_kSetupDone) ?? false;
    loaded = true;
    _applyLanguage();
    notifyListeners();
  }

  Future<void> update({
    String? serverUrl,
    String? userId,
    bool? sendToServer,
    int? uploadSeconds,
    bool? alertsOn,
    bool? vibrate,
    bool? keepScreenOn,
    int? historyDays,
    String? glucoseUnit,
    String? language,
    bool? setupDone,
  }) async {
    if (serverUrl != null) this.serverUrl = serverUrl.trim();
    if (userId != null) this.userId = userId.trim();
    if (sendToServer != null) this.sendToServer = sendToServer;
    if (uploadSeconds != null) this.uploadSeconds = uploadSeconds;
    if (alertsOn != null) this.alertsOn = alertsOn;
    if (vibrate != null) this.vibrate = vibrate;
    if (keepScreenOn != null) this.keepScreenOn = keepScreenOn;
    if (historyDays != null) this.historyDays = historyDays;
    if (glucoseUnit != null) this.glucoseUnit = glucoseUnit;
    if (language != null) {
      this.language = language;
      _applyLanguage();
    }
    if (setupDone != null) this.setupDone = setupDone;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, this.serverUrl);
    await p.setString(_kUser, this.userId);
    await p.setBool(_kSend, this.sendToServer);
    await p.setInt(_kInterval, this.uploadSeconds);
    await p.setBool(_kAlerts, this.alertsOn);
    await p.setBool(_kVibrate, this.vibrate);
    await p.setBool(_kAwake, this.keepScreenOn);
    await p.setInt(_kHistory, this.historyDays);
    await p.setString(_kGlucose, this.glucoseUnit);
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
