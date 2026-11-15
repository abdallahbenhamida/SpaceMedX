import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/recorder.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The ECG as it arrives: a scrolling trace on an ECG grid (small squares
/// 0.2 s, a heavier line every second). Repaints on every packet without
/// rebuilding anything else.
class LiveEcgChart extends StatefulWidget {
  const LiveEcgChart({super.key, this.recorder, this.seconds = 6, this.height = 150});

  final Recorder? recorder;

  /// How many seconds of signal fit on the screen.
  final int seconds;
  final double height;

  @override
  State<LiveEcgChart> createState() => _LiveEcgChartState();
}

class _LiveEcgChartState extends State<LiveEcgChart> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // repaint now and then, so "Signal lost" appears when packets stop
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recorder ?? Recorder.instance;
    final seconds = widget.seconds;
    final height = widget.height;
    return Semantics(
      label: tr('Live ECG trace'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: EcgPainter(rec, seconds)),
        ),
      ),
    );
  }
}

class EcgPainter extends CustomPainter {
  EcgPainter(this.rec, this.seconds) : super(repaint: rec.ecgTick);

  final Recorder rec;
  final int seconds;

  /// No packet for this long = the signal is gone.
  static const Duration staleAfter = Duration(seconds: 3);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF06101F));

    final window = Recorder.ecgSampleRate * seconds;
    final all = rec.ecg;
    final n = math.min(all.length, window);
    final data = n == 0 ? const <double>[] : all.sublist(all.length - n);

    // grid: small squares every 0.2 s, a stronger line every second
    final perSecond = size.width / seconds;
    final minor = Paint()
      ..color = SpaceColors.line.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = SpaceColors.line.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    for (var i = 0; i <= seconds * 5; i++) {
      final x = i * perSecond / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
    }
    final rows = (size.height / (perSecond / 5)).floor();
    for (var j = 0; j <= rows; j++) {
      final y = size.height - j * perSecond / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), j % 5 == 0 ? major : minor);
    }

    final last = rec.ecgLastAt;
    final live = last != null && DateTime.now().difference(last) < staleAfter;

    if (data.length < 2) {
      _label(canvas, size, tr('Waiting for the ECG signal …'));
      return;
    }

    // vertical scale from the data on screen (never tighter than 40 units)
    var lo = data.first, hi = data.first;
    for (final v in data) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (hi - lo < 40) {
      final mid = (hi + lo) / 2;
      lo = mid - 20;
      hi = mid + 20;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;

    // the newest sample is at the right edge
    final step = size.width / window;
    final x0 = size.width - (data.length - 1) * step;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = x0 + i * step;
      final y = size.height - (data[i] - lo) / (hi - lo) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = live ? SpaceColors.go : SpaceColors.muted,
    );
    if (!live) _label(canvas, size, tr('Signal lost'));
  }

  void _label(Canvas canvas, Size size, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: SpaceColors.muted, fontSize: 15)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(EcgPainter old) => true; // cheap, and the "signal lost" state depends on the clock
}
