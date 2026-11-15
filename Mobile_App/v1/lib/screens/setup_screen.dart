import 'package:flutter/material.dart';

import '../core/recorder.dart';
import '../core/server_client.dart';
import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/sensor_chooser.dart';
import '../widgets/server_fields.dart';
import 'setup_wizard.dart';
import 'watch_screen.dart';

/// All the options, in plain groups. Everything is saved as it is changed.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _s = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _group(Icons.language, 'Language', null, [
              DropdownButtonFormField<String>(
                initialValue: _s.language,
                isExpanded: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.translate)),
                dropdownColor: SpaceColors.panelHigh,
                items: [
                  DropdownMenuItem(value: 'system', child: Text(tr('Device language'))),
                  for (final l in supportedLangs) DropdownMenuItem(value: l.code, child: Text(l.name)),
                ],
                onChanged: (v) => _s.update(language: v),
              ),
            ]),
            const SizedBox(height: 14),
            _group(Icons.sensors, 'Sensor',
                'Which sensor do you wear? Pick one. "Demo sensor" lets you try the app without hardware.', const [
              SensorChooser(),
            ]),
            const SizedBox(height: 14),
            _group(Icons.watch, 'Galaxy Watch', 'Also collect data from your Samsung Galaxy Watch.', [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: _s.useWatch,
                onChanged: (v) => _s.update(useWatch: v),
                title: Text(tr('Use my watch'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              if (_s.useWatch)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WatchScreen())),
                  icon: const Icon(Icons.watch),
                  label: Text(tr('Connect or pair the watch')),
                ),
            ]),
            const SizedBox(height: 14),
            _group(Icons.dns_outlined, 'Server (optional)',
                'Without a server the app works on this phone alone and keeps your data here. You can add a server later in Settings.', [
              const ServerFields(),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: _s.sendToServer,
                onChanged: _s.serverConfigured ? (v) => _s.update(sendToServer: v) : null,
                title: Text(tr('Send data to the server'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  !_s.serverConfigured
                      ? tr('No server: the data stays on this phone.')
                      : (_s.sendToServer ? tr('Data is also kept on this phone.') : tr('Off: data stays on this phone only.')),
                  style: const TextStyle(color: SpaceColors.muted),
                ),
              ),
              if (_s.serverConfigured) ...[
                const SizedBox(height: 6),
                Text(tr('Send every'), style: const TextStyle(color: SpaceColors.muted, fontSize: 14)),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: _segStyle,
                  segments: [
                    const ButtonSegment(value: 5, label: Text('5 s')),
                    const ButtonSegment(value: 10, label: Text('10 s')),
                    const ButtonSegment(value: 30, label: Text('30 s')),
                    ButtonSegment(value: 60, label: Text(tr('1 min'))),
                  ],
                  selected: {_s.uploadSeconds},
                  onSelectionChanged: (v) => _s.update(uploadSeconds: v.first),
                ),
                ValueListenableBuilder<UploadStats>(
                  valueListenable: ServerClient.instance.stats,
                  builder: (context, st, _) => st.waiting > 0
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(tr('{n} records are waiting on this phone for the server.', {'n': st.waiting}),
                              style: const TextStyle(color: SpaceColors.muted, fontSize: 14)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
            const SizedBox(height: 14),
            _group(Icons.notifications_active_outlined, 'Alerts', 'What happens when a value is outside the normal range.', [
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
            ]),
            const SizedBox(height: 14),
            _group(Icons.tune, 'Display', null, [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: _s.keepScreenOn,
                onChanged: (v) => _s.update(keepScreenOn: v),
                title: Text(tr('Keep the screen on while collecting'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              Text(tr('Glucose unit'), style: const TextStyle(color: SpaceColors.muted, fontSize: 14)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: _segStyle,
                segments: const [
                  ButtonSegment(value: 'mmol', label: Text('mmol/L')),
                  ButtonSegment(value: 'mgdl', label: Text('mg/dL')),
                ],
                selected: {_s.glucoseUnit},
                onSelectionChanged: (v) => _s.update(glucoseUnit: v.first),
              ),
            ]),
            const SizedBox(height: 14),
            _group(Icons.storage_outlined, 'Data on this phone', 'Measurements are kept here for the charts.', [
              Text(tr('Keep for'), style: const TextStyle(color: SpaceColors.muted, fontSize: 14)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: _segStyle,
                segments: [
                  ButtonSegment(value: 7, label: Text(tr('{n} days', {'n': 7}))),
                  ButtonSegment(value: 30, label: Text(tr('{n} days', {'n': 30}))),
                  ButtonSegment(value: 90, label: Text(tr('{n} days', {'n': 90}))),
                ],
                selected: {_s.historyDays},
                onSelectionChanged: (v) {
                  _s.update(historyDays: v.first);
                  Recorder.instance.purgeOld();
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _confirmClear,
                style: OutlinedButton.styleFrom(foregroundColor: SpaceColors.stop),
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Delete the data on this phone')),
              ),
            ]),
            const SizedBox(height: 14),
            _group(Icons.bug_report_outlined, 'About and diagnostics', null, [
              const Text('SpaceMedX 1.5.0', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                tr('Research and wellness tool. Not a medical device and not a diagnosis.'),
                style: const TextStyle(color: SpaceColors.muted, fontSize: 14),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupWizard())),
                icon: const Icon(Icons.replay),
                label: Text(tr('Show the setup steps again')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _LogScreen())),
                icon: const Icon(Icons.list_alt),
                label: Text(tr('Show the event log')),
              ),
            ]),
          ],
        );
      },
    );
  }

  static final ButtonStyle _segStyle = SegmentedButton.styleFrom(
    backgroundColor: SpaceColors.panelHigh,
    selectedBackgroundColor: SpaceColors.blue,
    selectedForegroundColor: Colors.white,
    foregroundColor: SpaceColors.muted,
    side: const BorderSide(color: SpaceColors.line),
  );

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: SpaceColors.panel,
        title: Text(tr('Delete the data?')),
        content: Text(tr(
            'All measurements kept on this phone are deleted. Data already sent to the server stays there. This cannot be undone.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Delete'), style: const TextStyle(color: SpaceColors.stop)),
          ),
        ],
      ),
    );
    if (yes == true) {
      await Recorder.instance.store.clearObservations();
      Recorder.instance.resetLive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('The data on this phone was deleted.'))));
      }
    }
  }

  Widget _group(IconData icon, String title, String? help, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: SpaceColors.blue),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(title), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              ],
            ),
            if (help != null) ...[
              const SizedBox(height: 6),
              Text(tr(help), style: const TextStyle(fontSize: 14, color: SpaceColors.muted)),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LogScreen extends StatelessWidget {
  const _LogScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Event log'))),
      body: ListenableBuilder(
        listenable: AppLog.instance,
        builder: (context, _) {
          final lines = AppLog.instance.lines.reversed.toList();
          if (lines.isEmpty) {
            return Center(child: Text(tr('Nothing yet.'), style: const TextStyle(color: SpaceColors.muted)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: lines.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(lines[i],
                  textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            ),
          );
        },
      ),
    );
  }
}
