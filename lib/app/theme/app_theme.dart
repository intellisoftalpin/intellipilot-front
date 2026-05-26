import 'package:flutter/material.dart';

/// Builds [ThemeData] for a given seed color, brightness, and optional
/// platform-supplied dynamic [ColorScheme].
class AppTheme {
  const AppTheme._();

  static ThemeData light({
    required Color seedColor,
    ColorScheme? dynamicScheme,
  }) {
    final scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor);
    return _base(scheme);
  }

  static ThemeData dark({
    required Color seedColor,
    ColorScheme? dynamicScheme,
  }) {
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
      ),
    );
  }
}

class SeedPalette {
  const SeedPalette._();

  /// Curated palette for the in-app theme picker.
  static const List<({String name, Color color})> options = [
    (name: 'Indigo', color: Color(0xFF4A6CF7)),
    (name: 'Violet', color: Color(0xFF7C3AED)),
    (name: 'Teal', color: Color(0xFF0E9F8E)),
    (name: 'Emerald', color: Color(0xFF10B981)),
    (name: 'Amber', color: Color(0xFFF59E0B)),
    (name: 'Rose', color: Color(0xFFE11D48)),
    (name: 'Slate', color: Color(0xFF475569)),
  ];

  static const Color defaultSeed = Color(0xFF4A6CF7);
}
