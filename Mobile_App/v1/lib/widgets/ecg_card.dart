import 'package:flutter/material.dart';

import '../core/recorder.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'live_ecg_chart.dart';

/// The live ECG in a card (Home and Data).
class EcgCard extends StatelessWidget {
  const EcgCard({super.key, this.recorder, this.height = 150, this.compact = false});
  final Recorder? recorder;
  final double height;

  /// Less padding and no explanation text (for the Home screen).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart, color: SpaceColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('ECG, live'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                const Text('125 Hz', style: TextStyle(color: SpaceColors.muted, fontSize: 13)),
              ],
            ),
            SizedBox(height: compact ? 6 : 10),
            LiveEcgChart(recorder: recorder, height: height),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text(
                tr('The ECG is shown here. The app does not judge it.'),
                style: const TextStyle(color: SpaceColors.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
