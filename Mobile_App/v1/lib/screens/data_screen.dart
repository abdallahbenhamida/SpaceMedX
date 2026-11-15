import 'dart:async';

import 'package:flutter/material.dart';

import '../core/analysis.dart';
import '../core/recorder.dart';
import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/ecg_card.dart';
import '../widgets/range_chart.dart';

/// The data on this phone: a chart per measurement with the normal and
/// abnormal ranges behind it, the newest value, and a short analysis.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key, Recorder? recorder}) : _recorder = recorder;
  final Recorder? _recorder;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _Window {
  const _Window(this.label, this.duration);
  final String label;
  final Duration duration;
}

const _windows = [
  _Window('15 min', Duration(minutes: 15)),
  _Window('1 hour', Duration(hours: 1)),
  _Window('24 hours', Duration(hours: 24)),
  _Window('7 days', Duration(days: 7)),
];

class _Loaded {
  _Loaded(this.from, this.to, this.series);
  final DateTime from;
  final DateTime to;
  final Map<String, List<Point>> series;
}

class _DataScreenState extends State<DataScreen> {
  late final Recorder _rec = widget._recorder ?? Recorder.instance;
  int _w = 1;
  Timer? _timer;
  Future<_Loaded>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<_Loaded> _load() async {
    final to = DateTime.now();
    final from = to.subtract(_windows[_w].duration);
    final map = <String, List<Point>>{};
    Set<String> present;
    try {
      present = await _rec.store.paramsWithData(from, to);
    } catch (_) {
      present = {};
    }
    for (final id in present) {
      try {
        map[id] = await _rec.store.series(id, from, to);
      } catch (_) {
        map[id] = const [];
      }
    }
    return _Loaded(from, to, map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(tr('Data'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_rec, AppSettings.instance]),
          builder: (context, _) => FutureBuilder<_Loaded>(
            future: _future,
            builder: (context, snap) {
              final d = snap.data;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _windowPicker(),
                  const SizedBox(height: 12),
                  if (d == null)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _overview(d),
                    const SizedBox(height: 12),
                    if (_rec.alerts.isNotEmpty) ...[_alerts(), const SizedBox(height: 12)],
                    for (final card in _cards(d)) ...[card, const SizedBox(height: 12)],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _windowPicker() {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: SpaceColors.panel,
        selectedBackgroundColor: SpaceColors.blue,
        selectedForegroundColor: Colors.white,
        foregroundColor: SpaceColors.muted,
        side: const BorderSide(color: SpaceColors.line),
      ),
      segments: [for (var i = 0; i < _windows.length; i++) ButtonSegment(value: i, label: Text(tr(_windows[i].label)))],
      selected: {_w},
      onSelectionChanged: (s) {
        _w = s.first;
        _reload();
      },
    );
  }

  /// One chart for every data type that has received data, nothing else. A
  /// single sensor gives a single chart; a watch with many data types gives
  /// many.
  List<Widget> _cards(_Loaded d) {
    final out = <Widget>[];
    bool has(String id) => (d.series[id] ?? const []).isNotEmpty;
    if (has('hr')) out.add(_paramCard(d, Ranges.heartRate, Icons.favorite));
    if (has('sys') || has('dia')) out.add(_bpCard(d));
    if (has('glu')) out.add(_paramCard(d, Ranges.glucose, Icons.bloodtype));
    for (final id in d.series.keys) {
      if (Ranges.byId(id) != null || !has(id)) continue;
      final def = _rec.defs[id];
      if (def != null) out.add(_paramCard(d, def, Icons.show_chart));
    }
    if (_rec.ecg.isNotEmpty) out.add(EcgCard(recorder: _rec, height: 170));
    return out;
  }

  /// One sentence on top: is everything normal?
  Widget _overview(_Loaded d) {
    var total = 0;
    var worst = Level.unknown;
    var alerts = 0;
    for (final def in _rec.defs.values) {
      if (!def.hasRanges) {
        total += (d.series[def.id] ?? const []).length;
        continue;
      }
      final s = SeriesSummary.of(def, d.series[def.id] ?? const []);
      total += s.count;
      alerts += s.alertCount;
      if (s.count > 0 && s.lastLevel.rank > worst.rank) worst = s.lastLevel;
    }
    late final Level level;
    late final String title;
    late final String text;
    if (total == 0 && _rec.ecg.isEmpty) {
      level = Level.unknown;
      title = tr('No data yet');
      text = tr('Press START on the home screen. The measurements appear here.');
    } else if (worst == Level.unknown) {
      level = Level.unknown;
      title = tr('Showing your data');
      text = tr('There is no normal range for these values, so the app does not judge them.');
    } else if (worst.isAlert) {
      level = worst;
      title = tr('Check your latest values');
      text = tr('At least one latest value is outside the normal range.');
    } else if (alerts > 0) {
      level = Level.attention;
      title = tr('Some values were abnormal earlier');
      text = tr('{n} value(s) in this period were outside the normal range. The latest ones are fine.', {'n': alerts});
    } else {
      level = worst == Level.attention ? Level.attention : Level.normal;
      title = worst == Level.attention ? tr('Slightly off') : tr('All values in the normal range');
      text = tr('Based on the data of this period. No data does not mean healthy.');
    }
    final c = levelColor(level);
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.7), width: 1.5),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(levelIcon(level), color: c, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 14, color: SpaceColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alerts() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: SpaceColors.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('Alerts'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                TextButton(onPressed: _rec.clearAlerts, child: Text(tr('Clear'))),
              ],
            ),
            for (final a in _rec.alerts.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(levelIcon(a.level), color: levelColor(a.level), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${_clock(a.time)}  ${a.titleText}: ${a.detailText}', style: const TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paramCard(_Loaded d, ParamDef def, IconData icon) {
    final pts = d.series[def.id] ?? const <Point>[];
    final sum = SeriesSummary.of(def, pts);
    final mg = def.id == 'glu' && AppSettings.instance.glucoseUnit == 'mgdl';
    final scale = mg ? 18.016 : 1.0;
    final unit = mg ? 'mg/dL' : def.unit;
    String fmt(double v) => mg ? (v * scale).toStringAsFixed(0) : def.format(v * scale);
    return _card(
      icon: icon,
      title: tr(def.name),
      big: sum.last == null ? '—' : fmt(sum.last!),
      unit: unit,
      level: sum.lastLevel,
      levelText: sum.last == null ? tr('No data') : tr(sum.lastLabel),
      when: sum.lastTime,
      chart: RangeChart(def: def, points: pts, from: d.from, to: d.to, scale: scale),
      analysis: _analysis(sum, fmt, ranges: def.hasRanges),
      def: def,
      scale: scale,
    );
  }

  Widget _bpCard(_Loaded d) {
    final s = Ranges.systolic, di = Ranges.diastolic;
    final sp = d.series['sys'] ?? const <Point>[];
    final dp = d.series['dia'] ?? const <Point>[];
    final ss = SeriesSummary.of(s, sp);
    final ds = SeriesSummary.of(di, dp);
    final has = ss.last != null && ds.last != null;
    final r = has ? Ranges.bloodPressure(ss.last!, ds.last!) : (level: Level.unknown, label: 'No data');
    return _card(
      icon: Icons.speed,
      title: tr('Blood pressure'),
      big: has ? '${ss.last!.round()}/${ds.last!.round()}' : '—',
      unit: 'mmHg',
      level: r.level,
      levelText: tr(r.label),
      when: ss.lastTime,
      chart: Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(tr('Systolic'), style: const TextStyle(color: SpaceColors.muted, fontSize: 13)),
            ),
          ),
          RangeChart(def: s, points: sp, from: d.from, to: d.to, height: 150),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(tr('Diastolic'), style: const TextStyle(color: SpaceColors.muted, fontSize: 13)),
            ),
          ),
          RangeChart(def: di, points: dp, from: d.from, to: d.to, height: 150),
        ],
      ),
      analysis: [
        if (ss.count > 0) '${tr('Systolic')}: ${_stats(ss, (v) => v.round().toString())}',
        if (ds.count > 0) '${tr('Diastolic')}: ${_stats(ds, (v) => v.round().toString())}',
        if (ss.count == 0) tr('No blood pressure measurement in this period.'),
      ],
      def: s,
      scale: 1,
      extraDef: di,
    );
  }

  List<String> _analysis(SeriesSummary s, String Function(double) fmt, {bool ranges = true}) {
    if (s.count == 0) return [tr('No measurement in this period.')];
    final out = <String>[_stats(s, fmt)];
    if (!ranges) {
      if (s.trend == Trend.rising) out.add(tr('The values are rising.'));
      if (s.trend == Trend.falling) out.add(tr('The values are falling.'));
      out.add(tr('No normal range is defined for this value.'));
      return out;
    }
    if (s.count >= SeriesSummary.minForTrend && s.normalShare != null) {
      out.add(tr('{p}% of the values were in the normal range.', {'p': (s.normalShare! * 100).round()}));
    } else {
      out.add(tr('Too few values for a share or a trend yet.'));
    }
    if (s.trend == Trend.rising) out.add(tr('The values are rising.'));
    if (s.trend == Trend.falling) out.add(tr('The values are falling.'));
    if (s.alertCount > 0) out.add(tr('{n} value(s) were abnormal.', {'n': s.alertCount}));
    return out;
  }

  String _stats(SeriesSummary s, String Function(double) fmt) =>
      tr('average {a}, lowest {lo}, highest {hi} ({n} values)',
          {'a': fmt(s.avg!), 'lo': fmt(s.min!), 'hi': fmt(s.max!), 'n': s.count});

  Widget _card({
    required IconData icon,
    required String title,
    required String big,
    required String unit,
    required Level level,
    required String levelText,
    required DateTime? when,
    required Widget chart,
    required List<String> analysis,
    required ParamDef def,
    required double scale,
    ParamDef? extraDef,
  }) {
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
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                if (def.hasRanges)
                  IconButton(
                  tooltip: tr('Normal ranges'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.info_outline, color: SpaceColors.muted),
                  onPressed: () => _showRanges(def, extraDef, scale, unit),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(big, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(unit, style: const TextStyle(fontSize: 16, color: SpaceColors.muted)),
                ),
                const Spacer(),
                if (def.hasRanges) LevelChip(level, text: levelText),
              ],
            ),
            if (when != null)
              Text(tr('measured {t}', {'t': _clock(when)}), style: const TextStyle(color: SpaceColors.muted, fontSize: 13)),
            const SizedBox(height: 10),
            chart,
            const SizedBox(height: 8),
            for (final a in analysis)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(a, style: const TextStyle(fontSize: 14, color: SpaceColors.muted)),
              ),
          ],
        ),
      ),
    );
  }

  void _showRanges(ParamDef def, ParamDef? extra, double scale, String unit) {
    Widget table(ParamDef d, double sc) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(d.name), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final b in d.bands)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 150, child: Text(_bandText(b, sc, d), style: const TextStyle(fontSize: 15))),
                    LevelChip(b.level, text: tr(b.label)),
                  ],
                ),
              ),
          ],
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpaceColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              table(def, scale),
              if (extra != null) ...[const SizedBox(height: 16), table(extra, 1)],
              const SizedBox(height: 14),
              Text('${tr('Source')}: ${tr(def.source)}${def.note.isEmpty ? '' : '. ${tr(def.note)}'}',
                  style: const TextStyle(color: SpaceColors.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                tr('These ranges help you read the numbers. They are not a diagnosis. Talk to your medical officer about values that worry you.'),
                style: const TextStyle(color: SpaceColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _bandText(Band b, double sc, ParamDef d) {
    String f(double v) => (v * sc).toStringAsFixed(sc == 1 ? d.decimals : 0);
    if (b.min == null) return tr('below {x}', {'x': f(b.max!)});
    if (b.max == null) return tr('{x} and above', {'x': f(b.min!)});
    return tr('{a} to {b}', {'a': f(b.min!), 'b': f(b.max!)});
  }

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '${two(t.hour)}:${two(t.minute)}:${two(t.second)}' : '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
  }
}
