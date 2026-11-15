import 'dart:math' as math;

import '../l10n/l10n.dart';

/// How a value is judged. "unknown" is NOT "normal": missing data must look
/// different from a good result (SRS 5.4).
enum Level {
  unknown('No data'),
  normal('Normal'),
  attention('Attention'),
  abnormal('Abnormal'),
  urgent('Urgent');

  const Level(this._key);
  final String _key;

  /// The word, in the language of the app.
  String get text => tr(_key);

  bool get isAlert => this == abnormal || this == urgent;
  int get rank => index; // unknown(0) < normal < attention < abnormal < urgent
}

/// One value range of a parameter: `min <= value < max`.
class Band {
  const Band(this.min, this.max, this.level, this.label);
  final double? min; // null = no lower limit
  final double? max; // null = no upper limit
  final Level level;
  final String label;

  bool contains(double v) => (min == null || v >= min!) && (max == null || v < max!);
}

/// A measured quantity with its normal / abnormal ranges.
class ParamDef {
  const ParamDef({
    required this.id,
    required this.name,
    required this.unit,
    required this.bands,
    required this.chartMin,
    required this.chartMax,
    required this.source,
    this.decimals = 0,
    this.note = '',
  });

  /// A data type without defined ranges (for example one of the watch sensors):
  /// it is charted and summarised but not judged.
  const ParamDef.plain({required this.id, required this.name, required this.unit, this.decimals = 0})
      : bands = const [],
        chartMin = 0,
        chartMax = 1,
        source = '',
        note = '';

  bool get hasRanges => bands.isNotEmpty;

  final String id;
  final String name;
  final String unit;
  final List<Band> bands;
  final double chartMin; // default chart scale
  final double chartMax;
  final String source; // where the ranges come from (shown in the app)
  final String note; // an extra remark on the ranges
  final int decimals;

  Band? bandOf(double v) {
    for (final b in bands) {
      if (b.contains(v)) return b;
    }
    return null;
  }

  Level levelOf(double v) => bandOf(v)?.level ?? Level.unknown;

  /// The range that counts as normal (for the green band in charts).
  (double, double)? get normalSpan {
    double? lo;
    double? hi;
    for (final b in bands) {
      if (b.level != Level.normal) continue;
      lo = (lo == null) ? b.min : (b.min == null ? lo : math.min(lo, b.min!));
      hi = (hi == null) ? b.max : (b.max == null ? hi : math.max(hi, b.max!));
    }
    if (lo == null || hi == null) return null;
    return (lo, hi);
  }

  String format(double v) {
    if (!hasRanges) return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return v.toStringAsFixed(decimals);
  }
}

/// The reference ranges used by the app.
///
/// IMPORTANT: blood pressure follows the Hungarian Hypertension Society (MHT)
/// classification, which is the ESH categories (optimal / normal /
/// high-normal / grade 1-3), as reproduced in Hungarian guideline summaries.
/// The heart rate and glucose ranges are general adult reference values that
/// are NOT yet checked against a Hungarian protocol. Replace [all] with the
/// mission's approved ranges before any medical use: this app is a research
/// and wellness tool, not a diagnosis.
class Ranges {
  Ranges._();

  static const String bpSource =
      'Magyar Hypertonia Társaság / ESH categories (optimal, normal, high-normal, grade 1-3)';
  static const String generalSource =
      'General adult reference values, not yet checked against a Hungarian protocol';

  static const heartRate = ParamDef(
    id: 'hr',
    name: 'Heart rate',
    unit: 'bpm',
    chartMin: 40,
    chartMax: 160,
    source: generalSource,
    note: 'Resting adult values: exercise raises the heart rate.',
    bands: [
      Band(null, 40, Level.urgent, 'Very low'),
      Band(40, 50, Level.abnormal, 'Low'),
      Band(50, 60, Level.attention, 'Slightly low'),
      Band(60, 100, Level.normal, 'Normal'),
      Band(100, 120, Level.attention, 'Fast'),
      Band(120, 150, Level.abnormal, 'Very fast'),
      Band(150, null, Level.urgent, 'Extremely fast'),
    ],
  );

  static const systolic = ParamDef(
    id: 'sys',
    name: 'Blood pressure, systolic',
    unit: 'mmHg',
    chartMin: 70,
    chartMax: 200,
    source: bpSource,
    bands: [
      Band(null, 80, Level.abnormal, 'Too low'),
      Band(80, 90, Level.attention, 'Low'),
      Band(90, 120, Level.normal, 'Optimal'),
      Band(120, 130, Level.normal, 'Normal'),
      Band(130, 140, Level.attention, 'High-normal'),
      Band(140, 160, Level.abnormal, 'Grade 1 hypertension'),
      Band(160, 180, Level.abnormal, 'Grade 2 hypertension'),
      Band(180, null, Level.urgent, 'Grade 3 hypertension'),
    ],
  );

  static const diastolic = ParamDef(
    id: 'dia',
    name: 'Blood pressure, diastolic',
    unit: 'mmHg',
    chartMin: 40,
    chartMax: 130,
    source: bpSource,
    bands: [
      Band(null, 50, Level.abnormal, 'Too low'),
      Band(50, 60, Level.attention, 'Low'),
      Band(60, 80, Level.normal, 'Optimal'),
      Band(80, 85, Level.normal, 'Normal'),
      Band(85, 90, Level.attention, 'High-normal'),
      Band(90, 100, Level.abnormal, 'Grade 1 hypertension'),
      Band(100, 110, Level.abnormal, 'Grade 2 hypertension'),
      Band(110, null, Level.urgent, 'Grade 3 hypertension'),
    ],
  );

  static const glucose = ParamDef(
    id: 'glu',
    name: 'Blood glucose',
    unit: 'mmol/L',
    decimals: 1,
    chartMin: 2,
    chartMax: 16,
    source: generalSource,
    note: 'Fasting / before-meal values.',
    bands: [
      Band(null, 3.0, Level.urgent, 'Very low'),
      Band(3.0, 3.9, Level.abnormal, 'Low'),
      Band(3.9, 5.6, Level.normal, 'Normal'),
      Band(5.6, 7.0, Level.attention, 'Raised'),
      Band(7.0, 16.7, Level.abnormal, 'High'),
      Band(16.7, null, Level.urgent, 'Very high'),
    ],
  );

  static const List<ParamDef> all = [heartRate, systolic, diastolic, glucose];

  static ParamDef? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Blood pressure is judged on both numbers: the worse one counts.
  static ({Level level, String label}) bloodPressure(double sys, double dia) {
    final s = systolic.bandOf(sys);
    final d = diastolic.bandOf(dia);
    if (s == null && d == null) return (level: Level.unknown, label: 'No data');
    if (d == null) return (level: s!.level, label: s.label);
    if (s == null) return (level: d.level, label: d.label);
    return d.level.rank > s.level.rank ? (level: d.level, label: d.label) : (level: s.level, label: s.label);
  }
}

/// One point of a series.
class Point {
  const Point(this.time, this.value, {this.min, this.max});
  final DateTime time;
  final double value; // average of the bucket
  final double? min;
  final double? max;
}

enum Trend { rising, falling, steady, unknown }

/// What the app says about a series of values.
class SeriesSummary {
  const SeriesSummary({
    required this.count,
    this.min,
    this.max,
    this.avg,
    this.last,
    this.lastTime,
    this.lastLevel = Level.unknown,
    this.lastLabel = 'No data',
    this.normalShare,
    this.alertCount = 0,
    this.trend = Trend.unknown,
  });

  final int count;
  final double? min;
  final double? max;
  final double? avg;
  final double? last;
  final DateTime? lastTime;
  final Level lastLevel;
  final String lastLabel;

  /// Share of the values that were normal, 0..1 (null without data).
  final double? normalShare;
  final int alertCount; // values that were abnormal or urgent
  final Trend trend;

  /// Fewer values than this say too little for a trend or a share.
  static const int minForTrend = 5;

  static SeriesSummary of(ParamDef def, List<Point> points) {
    if (points.isEmpty) return const SeriesSummary(count: 0);
    var lo = double.infinity;
    var hi = -double.infinity;
    var sum = 0.0;
    var normal = 0;
    var alerts = 0;
    for (final p in points) {
      lo = math.min(lo, p.min ?? p.value);
      hi = math.max(hi, p.max ?? p.value);
      sum += p.value;
      final l = def.levelOf(p.value);
      if (l == Level.normal) normal++;
      if (l.isAlert) alerts++;
    }
    final last = points.last;
    final band = def.bandOf(last.value);
    return SeriesSummary(
      count: points.length,
      min: lo,
      max: hi,
      avg: sum / points.length,
      last: last.value,
      lastTime: last.time,
      lastLevel: band?.level ?? Level.unknown,
      lastLabel: band?.label ?? 'No data',
      normalShare: normal / points.length,
      alertCount: alerts,
      trend: _trend(def, points),
    );
  }

  /// Least-squares slope over the points, judged against the chart scale.
  static Trend _trend(ParamDef def, List<Point> points) {
    if (points.length < minForTrend) return Trend.unknown;
    final t0 = points.first.time.millisecondsSinceEpoch.toDouble();
    final n = points.length;
    var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0;
    for (final p in points) {
      final x = (p.time.millisecondsSinceEpoch - t0) / 3600000.0; // hours
      sx += x;
      sy += p.value;
      sxy += x * p.value;
      sxx += x * x;
    }
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) return Trend.steady;
    final slope = (n * sxy - sx * sy) / den; // units per hour
    final spanHours = (points.last.time.millisecondsSinceEpoch - t0) / 3600000.0;
    final change = slope * spanHours; // change over the whole window
    var span = def.chartMax - def.chartMin;
    if (!def.hasRanges) {
      var lo = points.first.value, hi = points.first.value;
      for (final p in points) {
        lo = math.min(lo, p.value);
        hi = math.max(hi, p.value);
      }
      span = hi - lo;
    }
    final threshold = span * 0.06;
    if (change > threshold) return Trend.rising;
    if (change < -threshold) return Trend.falling;
    return Trend.steady;
  }
}
