import 'dart:async';

import 'package:flutter/material.dart';

import '../core/analysis.dart';
import '../core/recorder.dart';
import '../core/server_client.dart';
import '../core/session.dart';
import '../core/settings.dart';
import '../core/sources.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';
import '../widgets/iss_strip.dart';
import '../widgets/range_chart.dart';
import 'app_shell.dart';
import 'setup_wizard.dart';

/// The only screen an astronaut needs, all on one page without scrolling:
/// the START / STOP button, the chart, the health alerts, and (very small, at
/// the bottom) what the server connection is doing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, MonitorSession? session}) : _session = session;
  final MonitorSession? _session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MonitorSession _session = widget._session ?? MonitorSession.instance;
  final AppSettings _settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    // First start: the setup steps (every step can be skipped).
    if (!_settings.setupDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupWizard()));
      });
    }
  }

  Future<void> _toggle() async {
    if (_session.isRunning) {
      await _session.stop();
      return;
    }
    final why = _session.cannotStartReason;
    if (why != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(tr(why))));
      AppShell.tab.value = 2; // Settings
      return;
    }
    await _session.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_session, _settings, Recorder.instance]),
      builder: (context, _) {
        final running = _session.isRunning;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: LayoutBuilder(
                builder: (context, box) {
                  const iss = 70.0, status = 74.0, alerts = 74.0, server = 26.0, gaps = 30.0;
                  final rest = box.maxHeight - iss - status - alerts - server - gaps;
                  // the button takes what the chart does not need
                  final buttonBox = (rest - 150).clamp(140.0, 280.0);
                  final chartH = (rest - buttonBox).clamp(100.0, 1000.0);
                  final s = buttonBox / 1.2;
                  return Column(
                    children: [
                      const SizedBox(height: iss, child: IssStrip()),
                      const SizedBox(height: 4),
                      SizedBox(height: status, child: _StatusText(session: _session)),
                      SizedBox(
                        height: buttonBox,
                        child: Center(child: BigStartStopButton(running: running, onPressed: _toggle, size: s)),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(height: chartH, child: _HomeChart(height: chartH)),
                      const SizedBox(height: 8),
                      SizedBox(height: alerts, child: _AlertCard(onTap: () => AppShell.tab.value = 1)),
                      const SizedBox(height: 4),
                      SizedBox(height: server, child: _ServerLine(running: running)),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusText extends StatelessWidget {
  const _StatusText({required this.session});
  final MonitorSession session;

  @override
  Widget build(BuildContext context) {
    late final String title;
    late String sub;
    late final Color color;
    var subColor = SpaceColors.muted;
    switch (session.state) {
      case SessionState.stopped:
        title = tr('Ready');
        sub = tr('Press START to begin');
        color = SpaceColors.text;
      case SessionState.starting:
        title = tr('Starting …');
        sub = tr('Connecting to your sensors');
        color = SpaceColors.cyan;
      case SessionState.running:
        title = tr('Collecting data');
        sub = _elapsed(session.elapsed);
        color = SpaceColors.go;
      case SessionState.attention:
        // a sensor problem, not a health problem: say so in plain words
        title = tr('Check the sensor');
        color = SpaceColors.warn;
        sub = '';
        for (final s in session.sources) {
          if (s.status.value.phase == SourcePhase.problem) {
            sub = '${tr(s.name)}: ${tr(s.status.value.text)}';
            break;
          }
        }
        subColor = SpaceColors.warn;
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Flexible(
          child: Text(sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: subColor)),
        ),
      ],
    );
  }

  static String _elapsed(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
}

// ---------------------------------------------------------------------------

/// The chart: the last values of the measurement that is coming in, with the
/// normal / abnormal ranges.
class _HomeChart extends StatefulWidget {
  const _HomeChart({required this.height});
  final double height;

  @override
  State<_HomeChart> createState() => _HomeChartState();
}

class _HomeChartState extends State<_HomeChart> {
  Timer? _timer;
  String _id = 'hr';
  List<Point> _points = const [];
  late DateTime _from = DateTime.now();
  late DateTime _to = DateTime.now();

  static const Map<String, Duration> _window = {
    'hr': Duration(minutes: 15),
    'sys': Duration(hours: 6),
    'glu': Duration(hours: 6),
  };

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Which measurement to show: the newest that came in (heart rate until something comes in).
  String _pick() {
    final l = Recorder.instance.latest;
    String? best;
    DateTime? bestTime;
    for (final id in const ['hr', 'sys', 'glu']) {
      final r = l[id];
      if (r != null && (bestTime == null || r.time.isAfter(bestTime))) {
        best = id;
        bestTime = r.time;
      }
    }
    if (best != null) return best;
    return 'hr';
  }

  Future<void> _reload() async {
    final id = _pick();
    final to = DateTime.now();
    final from = to.subtract(_window[id]!);
    List<Point> pts;
    try {
      pts = await Recorder.instance.store.series(id, from, to);
    } catch (_) {
      pts = const [];
    }
    if (!mounted) return;
    setState(() {
      _id = id;
      _points = pts;
      _from = from;
      _to = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final def = _id == 'sys' ? Ranges.systolic : Ranges.byId(_id)!;
    final l = Recorder.instance.latest;
    final mg = _id == 'glu' && AppSettings.instance.glucoseUnit == 'mgdl';
    final scale = mg ? 18.016 : 1.0;

    String value = '—';
    String unit = def.unit;
    Level level = Level.unknown;
    String label = '';
    if (_id == 'sys') {
      unit = 'mmHg';
      final s = l['sys'], d = l['dia'];
      if (s != null && d != null) {
        value = '${s.value.round()}/${d.value.round()}';
        final r = Ranges.bloodPressure(s.value, d.value);
        level = r.level;
        label = r.label;
      }
    } else {
      final r = l[_id];
      if (r != null) {
        value = mg ? (r.value * scale).toStringAsFixed(0) : def.format(r.value);
        level = r.level;
        label = r.label;
      }
      if (mg) unit = 'mg/dL';
    }
    final title = _id == 'sys' ? 'Blood pressure' : def.name;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          children: [
            Row(
              children: [
                Icon(_id == 'hr' ? Icons.favorite : (_id == 'sys' ? Icons.speed : Icons.bloodtype),
                    color: SpaceColors.blue, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(tr(title),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontSize: 12, color: SpaceColors.muted)),
                if (level != Level.unknown) ...[
                  const SizedBox(width: 8),
                  LevelChip(level, text: tr(label)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: RangeChart(
                def: def,
                points: _points,
                from: _from,
                to: _to,
                scale: scale,
                height: null,
                emptyText: tr('The chart appears when data arrives.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Health alerts only (values outside the normal range). Nothing about the
/// server or the sensors appears here.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.onTap});
  final VoidCallback onTap;

  HealthAlert? _recent() {
    final a = Recorder.instance.alerts;
    if (a.isEmpty) return null;
    return DateTime.now().difference(a.first.time) < const Duration(minutes: 10) ? a.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final on = AppSettings.instance.alertsOn;
    final alert = on ? _recent() : null;
    final Color c = alert == null ? SpaceColors.muted : levelColor(alert.level);
    final IconData icon = alert == null ? (on ? Icons.check_circle_outline : Icons.notifications_off_outlined) : levelIcon(alert.level);
    final String title = alert == null ? (on ? tr('No health alerts') : tr('Alerts are off')) : alert.titleText;
    final String? text = alert?.detailText;
    return Material(
      color: alert == null ? SpaceColors.panel : c.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: alert == null ? SpaceColors.line : c, width: alert == null ? 1 : 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: alert == null && on ? SpaceColors.go : c, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: alert == null ? SpaceColors.text : c)),
                    if (text != null)
                      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SpaceColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Very small and quiet: the server is not a health matter.
class _ServerLine extends StatelessWidget {
  const _ServerLine({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ValueListenableBuilder<UploadStats>(
      valueListenable: ServerClient.instance.stats,
      builder: (context, st, _) {
        late final IconData icon;
        late final String text;
        if (!s.sending) {
          icon = Icons.cloud_off_outlined;
          text = tr('No server: the data stays on this phone.');
        } else if (st.errorText != null) {
          icon = Icons.cloud_off_outlined;
          text = st.errorText!;
        } else if (st.lastOk != null) {
          icon = Icons.cloud_done_outlined;
          text = tr('Last sent at {t}', {'t': _clock(st.lastOk!)}) +
              (st.waiting > 0 ? ' · ${tr('{n} waiting on the phone', {'n': st.waiting})}' : '');
        } else {
          icon = Icons.cloud_queue;
          text = running ? tr('Waiting for the first data …') : tr('Server is set up');
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: SpaceColors.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: SpaceColors.muted, height: 1.15)),
            ),
          ],
        );
      },
    );
  }

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
