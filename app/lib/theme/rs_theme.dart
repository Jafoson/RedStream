import 'package:flutter/material.dart';

abstract final class Rs {
  // Core palette — matches RedStream CSS variables exactly
  static const bg = Color(0xFF17120E);
  static const panel = Color(0xFF1F1813);
  static const panel2 = Color(0xFF261D17);
  static const panel3 = Color(0xFF31251D);
  static const line = Color(0x17FFEED6);
  static const line2 = Color(0x2FFFEED6);
  static const text = Color(0xFFF6EDE0);
  static const muted = Color(0xFFB7A892);
  static const muted2 = Color(0xFF7D6F5E);
  static const accent = Color(0xFFD9824B);
  static const accentLight = Color(0xFFDFA070);
  static const gold = Color(0xFFE7B34A);

  // Radii
  static const radius = 18.0;
  static const radiusLg = 26.0;
  static const radiusSm = 13.0;

  // Layout constants
  static const sidebarW = 248.0;
  static const cardW = 200.0;
  static const cardH = 290.0;
  static const cwW = 310.0;
  static const cwH = 185.0;

  static Color glow([double a = 0.45]) => accent.withValues(alpha: a);

  static ThemeData theme() {
    const tt = TextTheme(
      displayLarge: TextStyle(
          fontSize: 46, fontWeight: FontWeight.w800, color: text, letterSpacing: -1.5),
      displayMedium: TextStyle(
          fontSize: 36, fontWeight: FontWeight.w800, color: text, letterSpacing: -1.0),
      titleLarge: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800, color: text, letterSpacing: -0.5),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text),
      bodyLarge: TextStyle(fontSize: 17, color: Color(0xFFD7D8DA), height: 1.5),
      bodyMedium: TextStyle(fontSize: 15, color: muted, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
      labelSmall: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: muted2),
    );
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      textTheme: tt,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: gold,
        surface: panel,
        onSurface: text,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        titleTextStyle: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: text),
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
    );
  }
}
