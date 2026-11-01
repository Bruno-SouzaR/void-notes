import 'package:flutter/material.dart';

/// Semantic design tokens for void-notes, grounded in the system topbar palette.
class VoidTheme {
  VoidTheme._();

  // Core Palette Tokens
  static const Color bg = Color(0xFF141414);
  static const Color pillBg = Color(0xFF1C1C1C);
  static const Color surface = Color(0xFF282828);
  static const Color accent = Color(0xFF1C594D);
  static const Color inactiveDot = Color(0xFF224E16);
  static const Color textPrimary = Color(0xFFE2E2E2);
  static const Color textSecondary = Color(0xFFEDEDED);
  static const Color border = Color(0xFF4C4141);
  static const Color success = Color(0xFF10B981);

  // Border Radii
  static const double radiusSmall = 6.0;
  static const double radiusCard = 16.0;
  static const double radiusPill = 30.0;

  // Global Flutter ThemeData configuration
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bg,
      cardColor: surface,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: inactiveDot,
        surface: surface,
        onPrimary: textPrimary,
        onSurface: textPrimary,
        outline: border,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1.0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: textSecondary),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
