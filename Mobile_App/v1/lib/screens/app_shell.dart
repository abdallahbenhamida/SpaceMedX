import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'data_screen.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

/// Three places only: Home (START / STOP), Data (charts and analysis) and
/// Settings.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Other screens switch tab through this.
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppShell.tab,
      builder: (context, i, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: i,
          children: const [
            HomeScreen(),
            DataScreen(),
            _SettingsPage(),
          ],
        ),
        // rebuilt when the language changes
        bottomNavigationBar: ListenableBuilder(
          listenable: AppSettings.instance,
          builder: (context, _) => NavigationBar(
            backgroundColor: SpaceColors.panel,
            indicatorColor: SpaceColors.blue.withValues(alpha: 0.28),
            selectedIndex: i,
            onDestinationSelected: (v) => AppShell.tab.value = v,
            labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.play_circle_outline), selectedIcon: const Icon(Icons.play_circle), label: tr('Home')),
              NavigationDestination(icon: const Icon(Icons.show_chart), selectedIcon: const Icon(Icons.show_chart), label: tr('Data')),
              NavigationDestination(
                  icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: tr('Settings')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(tr('Settings'))),
        body: const SafeArea(child: SettingsView()),
      ),
    );
  }
}
