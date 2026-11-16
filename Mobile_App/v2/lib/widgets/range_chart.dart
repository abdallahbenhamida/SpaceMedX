import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/analysis.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

Color levelColor(Level l) => switch (l) {
      Level.normal => SpaceColors.go,
      Level.attention => SpaceColors.warn,
      Level.abnormal => const Color(0xFFFF7A45),
      Level.urgent => SpaceColors.stop,
      Level.unknown => SpaceColors.muted,
    };

IconData levelIcon(Level l) => switch (l) {
      Level.normal => Icons.check_circle,
      Level.attention => Icons.info,
      Level.abnormal => Icons.warning_amber_rounded,
      Level.urgent => Icons.error,
      Level.unknown => Icons.help_outline,
    };

/// "Normal", "Abnormal" ... as a coloured chip. The icon and the word carry
/// the meaning as well, so it does not depend on colour alone.
class LevelChip extends StatelessWidget {
  const LevelChip(this.level, {super.key, this.text});
  final Level level;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(levelIcon(level), size: 16, color: c),
          const SizedBox(width: 5),
          Text(text ?? level.text, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

/// A line chart with the normal / abnormal ranges as coloured bands behind it.
class RangeChart extends StatelessWidget {
  const RangeChart({
    super.key,
    required this.def,
    required this.points,
    required this.from,
    required this.to,
    this.scale = 1,
    this.height = 190,
    this.legend = true,
    this.emptyText,
  });

  final ParamDef def;
  final List<Point> points;
  final DateTime from;
  final DateTime to;

  /// Display factor (for example mmol/L -> mg/dL).
  final double scale;

  /// Height of the whole chart. null = as high as the space it is given.
  final double? height;

  /// Show the colour key (normal / attention / abnormal / urgent) below.
  final bool legend;

  /// Shown instead of the chart while there is no data.
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final showKey = legend && def.hasRanges;
    final chart = points.isEmpty
        ? Center(
            child: Text(emptyText ?? tr('No data in this period'), textAlign: TextAlign.center, style: const TextStyle(color: SpaceColors.muted, fontSize: 15)),
          )
        : CustomPaint(size: Size.infinite, painter: _ChartPainter(def, points, from, to, scale));
    final body = Column(
      children: [
        Expanded(child: SizedBox(width: double.infinity, child: chart)),
        if (showKey) _Key(def),
      ],
    );
    if (height == null) return body;
    return SizedBox(height: height! + (showKey ? 24 : 0), width: double.infinity, child: body);
  }
}

/// Colour key: which colour means which range.
class _Key extends StatelessWidget {
  const _Key(this.def);
  final ParamDef def;

  @override
  Widget build(BuildContext context) {
    final levels = <Level>[];
    for (final b in def.bands) {
      if (!levels.contains(b.level)) levels.add(b.level);
    }
    levels.sort((a, b) => a.rank.compareTo(b.rank));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 2,
        children: [
          for (final l in levels)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: levelColor(l), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 5),
                Text(l.text, style: const TextStyle(color: SpaceColors.muted, fontSize: 11.5)),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.def, this.points, this.from, this.to, this.scale);
  final ParamDef def;
  final List<Point> points;
  final DateTime from;
  final DateTime to;
  final double scale;

  static const double left = 40, right = 8, top = 8, bottom = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

    // vertical scale: the default scale, widened if the data leaves it
    var lo = def.hasRanges ? def.chartMin : double.infinity;
    var hi = def.hasRanges ? def.chartMax : -double.infinity;
    for (final p in points) {
      lo = math.min(lo, p.min ?? p.value);
      hi = math.max(hi, p.max ?? p.value);
    }
    if (hi - lo < 1e-9) {
      lo -= 1; // a flat line still needs a scale
      hi += 1;
    }
    final pad = (hi - lo) * 0.04;
    lo -= pad;
    hi += pad;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    final t0 = from.millisecondsSinceEpoch.toDouble();
    final span = math.max(1, to.millisecondsSinceEpoch - t0);
    double x(DateTime t) => plot.left + (t.millisecondsSinceEpoch - t0) / span * plot.width;

    // range bands
    for (final b in def.bands) {
      final bLo = math.max(b.min ?? lo, lo);
      final bHi = math.min(b.max ?? hi, hi);
      if (bHi <= bLo) continue;
      final c = levelColor(b.level).withValues(alpha: b.level == Level.normal ? 0.26 : 0.17);
      canvas.drawRect(Rect.fromLTRB(plot.left, y(bHi), plot.right, y(bLo)), Paint()..color = c);
    }
    // a dashed line wherever the range changes colour
    final cuts = <double>{};
    for (final b in def.bands) {
      if (b.min != null) cuts.add(b.min!);
      if (b.max != null) cuts.add(b.max!);
    }
    for (final v in cuts) {
      if (v <= lo || v >= hi) continue;
      final below = def.levelOf(v - 1e-6), above = def.levelOf(v);
      if (below == above) continue;
      final worse = above.rank > below.rank ? above : below;
      _dashed(canvas, Offset(plot.left, y(v)), Offset(plot.right, y(v)),
          levelColor(worse == Level.normal ? Level.attention : worse).withValues(alpha: 0.55));
    }

    // grid + labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final grid = Paint()
      ..color = SpaceColors.line.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    const rows = 4;
    for (var i = 0; i <= rows; i++) {
      final v = lo + (hi - lo) * i / rows;
      final yy = y(v);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      _text(canvas, tp, (v * scale).toStringAsFixed(scale == 1 ? def.decimals : 0), Offset(2, yy - 7),
          const TextStyle(color: SpaceColors.muted, fontSize: 11));
    }
    _text(canvas, tp, _clock(from), Offset(plot.left, plot.bottom + 5),
        const TextStyle(color: SpaceColors.muted, fontSize: 11));
    final mid = DateTime.fromMillisecondsSinceEpoch(((from.millisecondsSinceEpoch + to.millisecondsSinceEpoch) / 2).round());
    _text(canvas, tp, _clock(mid), Offset(plot.center.dx - 16, plot.bottom + 5),
        const TextStyle(color: SpaceColors.muted, fontSize: 11));
    _text(canvas, tp, _clock(to), Offset(plot.right - 34, plot.bottom + 5),
        const TextStyle(color: SpaceColors.muted, fontSize: 11));

    // min..max of averaged buckets
    final rangePaint = Paint()
      ..color = SpaceColors.blue.withValues(alpha: 0.28)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final p in points) {
      if (p.min != null && p.max != null && p.max! > p.min!) {
        canvas.drawLine(Offset(x(p.time), y(p.min!)), Offset(x(p.time), y(p.max!)), rangePaint);
      }
    }

    // the line: every piece has the colour of the range its values are in
    if (!def.hasRanges) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final o = Offset(x(points[i].time), y(points[i].value));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = SpaceColors.cyan,
      );
    } else {
      final seg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < points.length; i++) {
        for (final s in splitSegment(def, points[i - 1].value, points[i].value)) {
          final a = Offset(x(points[i - 1].time) + (x(points[i].time) - x(points[i - 1].time)) * s.t0,
              y(s.v0));
          final b = Offset(x(points[i - 1].time) + (x(points[i].time) - x(points[i - 1].time)) * s.t1,
              y(s.v1));
          canvas.drawLine(a, b, seg..color = levelColor(s.level));
        }
      }
    }

    // points: every one when there are few, coloured by their level
    if (points.length <= 60) {
      for (final p in points) {
        final c = levelColor(def.levelOf(p.value));
        final o = Offset(x(p.time), y(p.value));
        canvas.drawCircle(o, 4.5, Paint()..color = SpaceColors.space);
        canvas.drawCircle(o, 3.5, Paint()..color = c);
      }
    } else {
      final p = points.last;
      canvas.drawCircle(Offset(x(p.time), y(p.value)), 5, Paint()..color = levelColor(def.levelOf(p.value)));
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dash = 5.0, gap = 4.0;
    var cx = a.dx;
    while (cx < b.dx) {
      canvas.drawLine(Offset(cx, a.dy), Offset(math.min(cx + dash, b.dx), a.dy), p);
      cx += dash + gap;
    }
  }

  static void _text(Canvas c, TextPainter tp, String s, Offset o, TextStyle st) {
    tp.text = TextSpan(text: s, style: st);
    tp.layout();
    tp.paint(c, o);
  }

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '${two(t.hour)}:${two(t.minute)}' : '${two(t.day)}.${two(t.month)}. ${two(t.hour)}h';
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.from != from || old.to != to || old.def != def || old.scale != scale;
}


/// One piece of a line between two values, inside a single range.
class SegmentPiece {
  const SegmentPiece(this.t0, this.t1, this.v0, this.v1, this.level);
  final double t0; // 0..1 along the segment
  final double t1;
  final double v0;
  final double v1;
  final Level level;
}

/// Cuts the line from [a] to [b] wherever it crosses the border between two
/// ranges, so each piece can be drawn in the colour of its own range.
List<SegmentPiece> splitSegment(ParamDef def, double a, double b) {
  final lo = math.min(a, b), hi = math.max(a, b);
  final ts = <double>[0, 1];
  if ((b - a).abs() > 1e-12) {
    for (final band in def.bands) {
      for (final edge in [band.min, band.max]) {
        if (edge != null && edge > lo && edge < hi) ts.add((edge - a) / (b - a));
      }
    }
  }
  ts.sort();
  final out = <SegmentPiece>[];
  for (var i = 1; i < ts.length; i++) {
    if (ts[i] - ts[i - 1] < 1e-9) continue;
    final v0 = a + (b - a) * ts[i - 1];
    final v1 = a + (b - a) * ts[i];
    out.add(SegmentPiece(ts[i - 1], ts[i], v0, v1, def.levelOf((v0 + v1) / 2)));
  }
  return out;
}
