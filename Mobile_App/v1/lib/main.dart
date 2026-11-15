import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'core/local_store.dart';
import 'core/recorder.dart';
import 'core/server_client.dart';
import 'core/settings.dart';
import 'l10n/l10n.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';
import 'widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: SpaceColors.space,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await AppSettings.instance.load();
  // Measurements and waiting uploads are kept in a database on the phone.
  try {
    final store = await SqliteStore.open();
    Recorder.instance.store = store;
    ServerClient.instance.store = store;
    await ServerClient.instance.restore();
    await Recorder.instance.purgeOld();
    await Recorder.instance.loadDefs();
  } catch (e) {
    AppLog.add('storage', 'database not available, data is kept in memory only: $e');
  }
  runApp(const SpaceMedXApp());
}

class SpaceMedXApp extends StatelessWidget {
  const SpaceMedXApp({super.key});

  @override
  Widget build(BuildContext context) {
    // rebuilt when the language is changed in the settings
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        title: 'SpaceMedX',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: L10n.locale,
        supportedLocales: [for (final l in supportedLangs) Locale(l.code)],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [const AppBackground(), if (child != null) child],
        ),
        home: const AppShell(),
      ),
    );
  }
}
