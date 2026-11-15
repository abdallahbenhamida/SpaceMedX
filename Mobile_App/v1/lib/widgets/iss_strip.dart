import 'package:flutter/material.dart';

import '../core/iss_env.dart';
import '../l10n/l10n.dart';
import '../ml/iss_env_model.dart';
import '../theme/app_theme.dart';

/// blue, light blue, green, yellow, red
Color issColor(IssLevel l) => switch (l) {
      IssLevel.veryLow => const Color(0xFF3B6FFF),
      IssLevel.low => const Color(0xFF7FD4FF),
      IssLevel.normal => SpaceColors.go,
      IssLevel.high => const Color(0xFFFFD23F),
      IssLevel.veryHigh => SpaceColors.stop,
    };

String issLevelText(IssLevel l) => tr(switch (l) {
      IssLevel.veryLow => 'Very low',
      IssLevel.low => 'Low',
      IssLevel.normal => 'Normal',
      IssLevel.high => 'High',
      IssLevel.veryHigh => 'Very high',
    });

String issName(IssVar v) => tr(switch (v) {
      IssVar.co2 => 'Carbon dioxide',
      IssVar.temperature => 'Temperature',
      IssVar.humidity => 'Humidity',
      IssVar.radiation => 'Radiation',
    });

IconData issIcon(IssVar v) => switch (v) {
      IssVar.co2 => Icons.air,
      IssVar.temperature => Icons.thermostat,
      IssVar.humidity => Icons.water_drop_outlined,
      IssVar.radiation => Icons.flare,
    };

String issValue(IssVar v, double x) => switch (v) {
      IssVar.co2 => x.round().toString(),
      IssVar.temperature => x.toStringAsFixed(1),
      IssVar.humidity => x.round().toString(),
      IssVar.radiation => x.toStringAsFixed(2),
    };

/// A very small strip of the ISS cabin air on top of Home. Each value has the colour of its level;
/// a tap opens the details.
class IssStrip extends StatefulWidget {
  const IssStrip({super.key, this.player});
  final IssEnvPlayer? player;

  @override
  State<IssStrip> createState() => _IssStripState();
}

class _IssStripState extends State<IssStrip> {
  late final IssEnvPlayer _p = widget.player ?? IssEnvPlayer.instance;

  @override
  void initState() {
    super.initState();
    _p.attach();
  }

  @override
  void dispose() {
    _p.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (context, _) {
        final byVar = {for (final a in _p.assessments) a.variable: a};
        return Material(
          color: SpaceColors.panel.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showIssDetails(context, _p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SpaceColors.line),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.satellite_alt, size: 18, color: SpaceColors.cyan),
                        const Text('ISS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: SpaceColors.cyan)),
                      ],
                    ),
                  ),
                  for (final v in IssVar.values) ...[
                    Expanded(child: _Chip(variable: v, a: byVar[v])),
                    if (v != IssVar.radiation) const SizedBox(width: 5),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.variable, required this.a});
  final IssVar variable;
  final IssAssessment? a;

  @override
  Widget build(BuildContext context) {
    final c = a == null ? SpaceColors.muted : issColor(a!.level);
    return Semantics(
      label: a == null ? issName(variable) : '${issName(variable)} ${issValue(variable, a!.value)} ${IssEnvModel.unitOf(variable)}, ${issLevelText(a!.level)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.withValues(alpha: 0.9), width: 1.4),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(issIcon(variable), size: 14, color: c),
              Text(a == null ? '—' : issValue(variable, a!.value),
                  maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, height: 1.1)),
              Text(IssEnvModel.unitOf(variable),
                  maxLines: 1, style: const TextStyle(fontSize: 9.5, color: SpaceColors.muted, height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The details of the ISS strip: level, usual range, jumps, where the data comes from.
Future<void> showIssDetails(BuildContext context, IssEnvPlayer p) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SpaceColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: ListenableBuilder(
          listenable: p,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.satellite_alt, color: SpaceColors.cyan),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr('ISS environment'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                ],
              ),
              const SizedBox(height: 12),
              for (final a in p.assessments) _Row(a),
              const SizedBox(height: 10),
              Text(
                tr('Recorded NASA data (mission {m}, {d}), replayed. Compared with usual ISS values, not a safety limit.',
                    {'m': p.mission, 'd': p.sampleTime == null ? '' : p.sampleTime!.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}),
                style: const TextStyle(color: SpaceColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                IssEnvModel.trained ? tr('AI model: trained') : tr('AI model: not trained yet, a simple rule is used'),
                style: const TextStyle(color: SpaceColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.a);
  final IssAssessment a;

  @override
  Widget build(BuildContext context) {
    final c = issColor(a.level);
    final unit = IssEnvModel.unitOf(a.variable);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: c)),
            child: Icon(issIcon(a.variable), color: c, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issName(a.variable), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(
                  tr('Usual range: {a} to {b} {u}', {
                    'a': issValue(a.variable, a.normalLow),
                    'b': issValue(a.variable, a.normalHigh),
                    'u': unit,
                  }),
                  style: const TextStyle(fontSize: 13, color: SpaceColors.muted),
                ),
                if (a.jump)
                  Text(tr('Changed faster than expected'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SpaceColors.warn)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${issValue(a.variable, a.value)} $unit', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: c)),
                child: Text(issLevelText(a.level), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
