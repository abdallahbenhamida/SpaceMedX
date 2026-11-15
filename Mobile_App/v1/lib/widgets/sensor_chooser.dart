import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

IconData sensorIcon(String id) => switch (id) {
      'EID_103' => Icons.monitor_heart,
      'EID_107' => Icons.favorite,
      'EID_102' || 'EID_108' => Icons.speed,
      'EID_101' => Icons.bloodtype,
      'demo' => Icons.science_outlined,
      _ => Icons.block,
    };

/// The list of sensors. Tapping one selects it. Only a sensor that needs a PIN
/// or a pairing step opens a pop-up for it, so the other settings are not
/// shown at all until they matter.
class SensorChooser extends StatelessWidget {
  const SensorChooser({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final s = AppSettings.instance;
        return Column(
          children: [
            for (final c in SensorChoice.all) _tile(context, c, selected: s.sensor == c.id, settings: s),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, SensorChoice c, {required bool selected, required AppSettings settings}) {
    final pinLine = selected && c.needsPin
        ? (settings.savvyPin.isEmpty ? tr('PIN missing: tap to enter it') : '${tr('PIN')}: ${'•' * settings.savvyPin.length}')
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? SpaceColors.panelHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => chooseSensor(context, c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? SpaceColors.blue : SpaceColors.line, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Icon(sensorIcon(c.id), color: selected ? SpaceColors.blue : SpaceColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(c.title), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      Text(tr(c.subtitle), style: const TextStyle(fontSize: 14, color: SpaceColors.muted)),
                      if (pinLine != null)
                        Text(pinLine,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: settings.savvyPin.isEmpty ? SpaceColors.warn : SpaceColors.cyan)),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, color: SpaceColors.blue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selects [c]. A sensor with a PIN or pairing steps first shows a pop-up.
Future<void> chooseSensor(BuildContext context, SensorChoice c) async {
  final s = AppSettings.instance;
  if (!c.needsPopup) {
    await s.update(sensor: c.id);
    return;
  }
  final r = await showDialog<({String pin, String channel})>(
    context: context,
    builder: (_) => _SensorDialog(choice: c),
  );
  if (r == null) return; // cancelled: nothing changes
  await s.update(sensor: c.id, savvyPin: c.needsPin ? r.pin : null, ecgChannel: c.needsPin ? r.channel : null);
}

class _SensorDialog extends StatefulWidget {
  const _SensorDialog({required this.choice});
  final SensorChoice choice;

  @override
  State<_SensorDialog> createState() => _SensorDialogState();
}

class _SensorDialogState extends State<_SensorDialog> {
  late final TextEditingController _pin = TextEditingController(text: AppSettings.instance.savvyPin);
  late String _channel = AppSettings.instance.ecgChannel;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  bool get _ok => !widget.choice.needsPin || _pin.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = widget.choice;
    return AlertDialog(
      backgroundColor: SpaceColors.panel,
      title: Text(tr(c.title)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.needsPin) ...[
              TextField(
                controller: _pin,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('PIN of the ECG recorder'),
                  hintText: tr('for example 9545'),
                  prefixIcon: const Icon(Icons.pin_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _channel,
                decoration: InputDecoration(
                  labelText: tr('ECG channel to send'),
                  prefixIcon: const Icon(Icons.stacked_line_chart),
                ),
                dropdownColor: SpaceColors.panelHigh,
                items: [
                  for (var i = 0; i < 10; i++) DropdownMenuItem(value: 'ch$i', child: Text('${tr('Channel')} $i')),
                ],
                onChanged: (v) => setState(() => _channel = v ?? _channel),
              ),
              const SizedBox(height: 16),
            ],
            Text(tr('How it connects'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SpaceColors.cyan)),
            const SizedBox(height: 6),
            for (var i = 0; i < c.steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: SpaceColors.blue,
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr(c.steps[i]), style: const TextStyle(fontSize: 15))),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        TextButton(
          onPressed: _ok ? () => Navigator.pop(context, (pin: _pin.text.trim(), channel: _channel)) : null,
          child: Text(tr('Use this sensor'), style: TextStyle(fontWeight: FontWeight.w800, color: _ok ? SpaceColors.blue : SpaceColors.muted)),
        ),
      ],
    );
  }
}
