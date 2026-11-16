import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The vertical SpaceMedX picture behind every screen, dimmed so the
/// controls in front stay easy to read.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: SpaceColors.space),
        Image.asset(
          'assets/images/logo_vertical.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        // darker at the top and the bottom, where text and bars sit
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB0040A18), Color(0x66040A18), Color(0x80040A18), Color(0xE6040A18)],
              stops: [0, 0.35, 0.65, 1],
            ),
          ),
        ),
      ],
    );
  }
}
