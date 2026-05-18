import 'package:flutter/material.dart';

/// Stitch "Minimalist Daily Lesson UI" palette — green daily, purple specific.
class LessonTheme {
  static const _background = Color(0xFFF9F9FC);
  static const _onSurface = Color(0xFF1A1C1E);
  static const _onSurfaceVariant = Color(0xFF404944);
  static const _outline = Color(0xFF707973);
  static const _outlineVariant = Color(0xFFBFC9C2);
  static const _surfaceContainer = Color(0xFFEEEEF0);
  static const _surfaceContainerLow = Color(0xFFF3F3F6);
  static const _surfaceContainerHighest = Color(0xFFE2E2E5);
  static const _surfaceContainerLowest = Color(0xFFFFFFFF);

  static const dailyPrimary = Color(0xFF24674F);
  static const dailyPrimaryContainer = Color(0xFF3F8067);
  static const dailyPrimaryFixed = Color(0xFFADF1D2);
  static const dailyOnPrimaryContainer = Color(0xFFF5FFF8);

  static const accentSecondary = Color(0xFF6B38D4);
  static const accentSecondaryContainer = Color(0xFF8455EF);
  static const accentSecondaryFixed = Color(0xFFE9DDFF);
  static const accentOnSecondary = Color(0xFFFFFFFF);

  static ColorScheme scheme({required bool isSpecific}) {
    if (isSpecific) {
      return const ColorScheme(
        brightness: Brightness.light,
        primary: accentSecondary,
        onPrimary: accentOnSecondary,
        primaryContainer: accentSecondaryContainer,
        onPrimaryContainer: accentOnSecondary,
        secondary: dailyPrimary,
        onSecondary: accentOnSecondary,
        secondaryContainer: dailyPrimaryFixed,
        onSecondaryContainer: dailyPrimary,
        tertiary: Color(0xFF565E5C),
        onTertiary: accentOnSecondary,
        tertiaryContainer: Color(0xFF6E7674),
        onTertiaryContainer: Color(0xFFF6FEFB),
        error: Color(0xFFBA1A1A),
        onError: accentOnSecondary,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF93000A),
        surface: _background,
        onSurface: _onSurface,
        surfaceContainerHighest: _surfaceContainerHighest,
        surfaceContainerHigh: Color(0xFFE8E8EA),
        surfaceContainer: _surfaceContainer,
        surfaceContainerLow: _surfaceContainerLow,
        surfaceContainerLowest: _surfaceContainerLowest,
        onSurfaceVariant: _onSurfaceVariant,
        outline: _outline,
        outlineVariant: _outlineVariant,
        shadow: Colors.black26,
        scrim: Colors.black54,
        inverseSurface: Color(0xFF2F3133),
        onInverseSurface: Color(0xFFF0F0F3),
        inversePrimary: dailyPrimaryFixed,
        surfaceTint: accentSecondary,
      );
    }

    return const ColorScheme(
      brightness: Brightness.light,
      primary: dailyPrimary,
      onPrimary: accentOnSecondary,
      primaryContainer: dailyPrimaryContainer,
      onPrimaryContainer: dailyOnPrimaryContainer,
      secondary: accentSecondary,
      onSecondary: accentOnSecondary,
      secondaryContainer: accentSecondaryContainer,
      onSecondaryContainer: accentOnSecondary,
      tertiary: Color(0xFF565E5C),
      onTertiary: accentOnSecondary,
      tertiaryContainer: Color(0xFF6E7674),
      onTertiaryContainer: Color(0xFFF6FEFB),
      error: Color(0xFFBA1A1A),
      onError: accentOnSecondary,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF93000A),
      surface: _background,
      onSurface: _onSurface,
      surfaceContainerHighest: _surfaceContainerHighest,
      surfaceContainerHigh: Color(0xFFE8E8EA),
      surfaceContainer: _surfaceContainer,
      surfaceContainerLow: _surfaceContainerLow,
      surfaceContainerLowest: _surfaceContainerLowest,
      onSurfaceVariant: _onSurfaceVariant,
      outline: _outline,
      outlineVariant: _outlineVariant,
      shadow: Colors.black26,
      scrim: Colors.black54,
      inverseSurface: Color(0xFF2F3133),
      onInverseSurface: Color(0xFFF0F0F3),
      inversePrimary: dailyPrimaryFixed,
      surfaceTint: dailyPrimary,
    );
  }

  static LinearGradient dailyCardGradient() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          dailyPrimaryFixed.withValues(alpha: 0.15),
          _surfaceContainerLowest,
        ],
      );

  static LinearGradient specificCardGradient() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accentSecondaryFixed.withValues(alpha: 0.2),
          _surfaceContainerLowest,
        ],
      );

  static LinearGradient wordCardGradient(ColorScheme cs) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          cs.primary.withValues(alpha: 0.05),
          _surfaceContainerLowest,
        ],
      );

  static BoxShadow cardShadow = BoxShadow(
    color: Colors.black.withValues(alpha: 0.04),
    blurRadius: 20,
    offset: const Offset(0, 4),
  );
}
