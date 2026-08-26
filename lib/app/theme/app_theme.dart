import 'package:flutter/material.dart';
import 'package:intellipilot/app/theme/status_palette.dart';

/// Builds [ThemeData] for a given seed color, brightness, and optional
/// platform-supplied dynamic [ColorScheme].
///
/// Brand identity (locked in 2026-05):
/// - Seed: `#5B5BD6` (IntelliPilot indigo-violet) — distinct from Atlassian
///   blue, reads as "smart / pilot".
/// - UI typeface: Plus Jakarta Sans (bundled — see `assets/fonts/`).
///   Deliberately NOT fetched at runtime: a downloaded typeface fails on a
///   sandboxed, offline or CSP-restricted host and greets the user with an
///   error box instead of text.
/// - Mono typeface for issue keys + code: JetBrains Mono.
/// - Status colours are NOT taxonomy-driven; they live in [StatusPalette]
///   and are registered as a [ThemeExtension] so components can resolve
///   them via `StatusPalette.of(context)`.
class AppTheme {
  const AppTheme._();

  /// Bundled family names. Must match the `family:` entries in pubspec.yaml
  /// exactly — a typo here silently falls back to the platform default rather
  /// than failing, so both names live in one place.
  static const _uiFont = 'Plus Jakarta Sans';
  static const _monoFont = 'JetBrains Mono';

  static ThemeData light({
    required Color seedColor,
    ColorScheme? dynamicScheme,
  }) {
    final scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor);
    return _base(scheme, isDark: false);
  }

  static ThemeData dark({
    required Color seedColor,
    ColorScheme? dynamicScheme,
  }) {
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
    return _base(scheme, isDark: true);
  }

  static ThemeData _base(ColorScheme scheme, {required bool isDark}) {
    // Plus Jakarta Sans for body + headings, JetBrains Mono for keys/code.
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    final textTheme = base.textTheme.apply(fontFamily: _uiFont);

    return base.copyWith(
      textTheme: textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      // Monospaced figures for issue keys etc.
      typography: Typography.material2021(platform: base.platform).copyWith(
        black: Typography.blackHelsinki,
        white: Typography.whiteHelsinki,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        indicatorColor: scheme.primaryContainer,
        useIndicator: true,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        labelStyle: textTheme.labelMedium,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[
        if (isDark) StatusPalette.dark else StatusPalette.light,
      ],
    );
  }

  /// Monospaced text style for issue keys (`US-10`, `EPIC-1`), code blocks,
  /// diff lines, and the keyboard-shortcut help chips.
  static TextStyle mono(BuildContext context, {double? size}) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return (base ?? const TextStyle()).copyWith(
      fontFamily: _monoFont,
      fontSize: size,
    );
  }
}

class SeedPalette {
  const SeedPalette._();

  /// Curated palette for the in-app theme picker. The default is the
  /// IntelliPilot indigo-violet brand colour.
  static const List<({String name, Color color})> options = [
    (name: 'IntelliPilot Indigo', color: Color(0xFF5B5BD6)),
    (name: 'Plum', color: Color(0xFF7C3AED)),
    (name: 'Teal', color: Color(0xFF0EA5A4)),
    (name: 'Emerald', color: Color(0xFF10B981)),
    (name: 'Amber', color: Color(0xFFF59E0B)),
    (name: 'Rose', color: Color(0xFFE11D48)),
    (name: 'Slate', color: Color(0xFF475569)),
  ];

  static const Color defaultSeed = Color(0xFF5B5BD6);
}
