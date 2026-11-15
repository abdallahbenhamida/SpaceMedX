import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The one big button of the app: green START, red STOP.
/// While running a ring pulses around it so it is obvious the app is working.
class BigStartStopButton extends StatefulWidget {
  const BigStartStopButton({
    super.key,
    required this.running,
    required this.onPressed,
    this.size = 232,
    this.enabled = true,
  });

  final bool running;
  final VoidCallback onPressed;
  final double size;
  final bool enabled;

  @override
  State<BigStartStopButton> createState() => _BigStartStopButtonState();
}

class _BigStartStopButtonState extends State<BigStartStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.running ? SpaceColors.stop : SpaceColors.go;
    final s = widget.size;
    return Semantics(
      button: true,
      label: widget.running ? tr('Stop') : tr('Start'),
      child: SizedBox(
        width: s * 1.2,
        height: s * 1.2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.running)
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return CustomPaint(
                    size: Size.square(s * 1.2),
                    painter: _RingPainter(color: color, t: t, base: s / 2),
                  );
                },
              ),
            // glow
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 48, spreadRadius: 4),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.enabled ? widget.onPressed : null,
                child: Ink(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.4),
                      radius: 1.0,
                      colors: [
                        Color.lerp(color, Colors.white, 0.28)!,
                        color,
                        Color.lerp(color, Colors.black, 0.35)!,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: s * 0.36,
                        color: Colors.white,
                      ),
                      Text(
                        widget.running ? tr('STOP') : tr('START'),
                        style: TextStyle(
                          fontSize: s * 0.17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.t, required this.base});
  final Color color;
  final double t;
  final double base;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final r = base + (maxR - base) * p;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - p) + 1
        ..color = color.withValues(alpha: math.max(0, 0.55 * (1 - p)));
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color;
}
