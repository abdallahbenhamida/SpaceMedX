import 'package:flutter/material.dart';

/// Colours taken from the SpaceMedX logo: deep space navy, electric blue,
/// white; plus the traffic-light colours of the big button.
class SpaceColors {
  SpaceColors._();

  static const space = Color(0xFF040A18); // background
  static const panel = Color(0xFF0C1630); // cards
  static const panelHigh = Color(0xFF14224A); // inputs, selected cards
  static const line = Color(0xFF22336B);
  static const blue = Color(0xFF1EA7FF); // brand ("X" of SpaceMedX)
  static const cyan = Color(0xFF4FD8FF);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFF93A6D1);

  static const go = Color(0xFF1FCB78); // START
  static const stop = Color(0xFFFF3B4E); // STOP
  static const warn = Color(0xFFFFB020);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: SpaceColors.blue,
    onPrimary: Colors.white,
    secondary: SpaceColors.cyan,
    surface: SpaceColors.panel,
    onSurface: SpaceColors.text,
    error: SpaceColors.stop,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    // transparent: the picture of the app is drawn behind every screen
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: SpaceColors.panel,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: SpaceColors.text,
      displayColor: SpaceColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SpaceColors.text),
    ),
    cardTheme: CardThemeData(
      color: SpaceColors.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: SpaceColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SpaceColors.panelHigh,
      labelStyle: const TextStyle(color: SpaceColors.muted),
      hintStyle: const TextStyle(color: Color(0xFF5F7096)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: SpaceColors.blue, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SpaceColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SpaceColors.cyan,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: SpaceColors.line, width: 1.5),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : SpaceColors.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? SpaceColors.blue : SpaceColors.panelHigh),
    ),
  );
}
