import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class AppTypography {
  static TextTheme get textTheme {
    return TextTheme(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.4,
        letterSpacing: -0.02 * 40,
        color: AppColors.onSurface,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.5,
        letterSpacing: -0.01 * 32,
        color: AppColors.onSurface,
      ),
      displaySmall: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: AppColors.onSurface,
      ),
      bodyLarge: GoogleFonts.lexend(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.7,
        color: AppColors.onSurface,
      ),
      bodyMedium: GoogleFonts.lexend(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.onSurface,
      ),
      labelMedium: GoogleFonts.lexend(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.6,
        letterSpacing: 0.02 * 14,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
