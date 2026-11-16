import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/server_fields.dart';

/// First start: one setting per step ("1/3"). Every step can be skipped, so
/// the app can be used at once, on the phone alone, without a server.
class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  /// Number of steps.
  static const int total = 3;

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  final _s = AppSettings.instance;
  int _step = 0;

  Future<void> _finish() async {
    await _s.update(setupDone: true);
    if (mounted) Navigator.of(context).pop();
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step >= SetupWizard.total - 1) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final last = _step == SetupWizard.total - 1;
        final optional = _step == 1; // the server
        return PopScope(
          canPop: false,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                    child: Row(
                      children: [
                        Text('${_step + 1}/${SetupWizard.total}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: SpaceColors.cyan)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (_step + 1) / SetupWizard.total,
                              minHeight: 8,
                              backgroundColor: SpaceColors.panelHigh,
                              color: SpaceColors.blue,
                            ),
                          ),
                        ),
                        TextButton(onPressed: _finish, child: Text(tr('Skip setup'))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      children: [
                        if (_step == 0) ...[
                          Text(tr('Welcome to SpaceMedX'),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 14),
                        ],
                        _body(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      children: [
                        if (_step > 0)
                          Expanded(
                            child: OutlinedButton(onPressed: _back, child: Text(tr('Back'))),
                          ),
                        if (_step > 0) const SizedBox(width: 12),
                        if (optional) ...[
                          TextButton(onPressed: _next, child: Text(tr('Skip'))),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          flex: 2,
                          child: FilledButton(onPressed: _next, child: Text(last ? tr('Finish') : tr('Next'))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _head(IconData icon, String title, String help) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: SpaceColors.blue, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(title), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 8),
          Text(tr(help), style: const TextStyle(fontSize: 15, color: SpaceColors.muted)),
          const SizedBox(height: 16),
        ],
      );

  Widget _body() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _head(Icons.language, 'Language', 'Choose your language.'),
            const LanguageList(),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _head(Icons.dns_outlined, 'Server (optional)',
                'Without a server the app works on this phone alone and keeps your data here. You can add a server later in Settings.'),
            const ServerFields(),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _head(Icons.notifications_active_outlined, 'Alerts and screen',
                'What happens when a value is outside the normal range.'),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              value: _s.alertsOn,
              onChanged: (v) => _s.update(alertsOn: v),
              title: Text(tr('Show alerts'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              value: _s.vibrate,
              onChanged: _s.alertsOn ? (v) => _s.update(vibrate: v) : null,
              title: Text(tr('Vibrate on an alert'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              value: _s.keepScreenOn,
              onChanged: (v) => _s.update(keepScreenOn: v),
              title: Text(tr('Keep the screen on while collecting'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ],
        );
    }
  }
}

/// Tiles to pick the language of the app.
class LanguageList extends StatelessWidget {
  const LanguageList({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    Widget tile(String code, String name) {
      final sel = s.language == code;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: sel ? SpaceColors.panelHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => s.update(language: code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sel ? SpaceColors.blue : SpaceColors.line, width: sel ? 2 : 1),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                  if (sel) const Icon(Icons.check_circle, color: SpaceColors.blue),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        tile('system', tr('Device language')),
        for (final l in supportedLangs) tile(l.code, l.name),
      ],
    );
  }
}
