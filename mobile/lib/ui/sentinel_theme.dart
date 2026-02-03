import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Rule: No hardcoded hex in UI. Use theme + SentinelColors tokens.
// Semantic status only may use AppColors.success / warning / error.
// For dividers/borders use theme.dividerColor (neutralBorder).
// ---------------------------------------------------------------------------

/// Premium light theme constants for Sentinel.
class SentinelColors {
  SentinelColors._();

  // Backgrounds
  static const Color bgPrimary = Color(0xFFF6F7FB);
  static const Color card = Colors.white;

  // Text
  static const Color textPrimary = Color(0xFF0D0D0D);
  static const Color textSecondary = Color(0xFF6B6B6B);

  // Brand
  static const Color primary = Color(0xFF111111); // Black CTA
  static const Color error = Color(0xFFB11226);

  // Resident accent: Pastel Teal / Aqua-Grey (canonical tokens)
  static const Color sentinelAccent = Color(0xFF7A9E9E);
  static Color get sentinelAccentSurface => sentinelAccent.withOpacity(0.04);
  static Color get sentinelAccentBorder => sentinelAccent.withOpacity(0.06);

  /// Canonical accent for resident UI. Use theme.colorScheme.primary for admin/guard.
  static Color get accent => sentinelAccent;
  /// Optional opacity (default 0.04). For surfaces/tints.
  static Color accentSurface([double opacity = 0.04]) => sentinelAccent.withOpacity(opacity);
  /// Border tint for accent areas.
  static Color get accentBorder => sentinelAccentBorder;

  // UI borders: use theme.dividerColor in widgets (neutralBorder). Fallback:
  static const Color border = Color(0xFFE6E6E6);
}

/// Notice board category colors (Event / Alert / Maintenance / Policy).
/// Muted, premium tones. Use [bg] for chip/card backgrounds, [icon] for icon tint.
class NoticeCategoryPalette {
  NoticeCategoryPalette._();

  static const Color event = Color(0xFF5A9A7A);       // green/teal muted
  static const Color alert = Color(0xFFB8863C);       // amber/orange muted
  static const Color maintenance = Color(0xFF6B8BA4); // blue-grey muted
  static const Color policy = Color(0xFF8B7A9E);      // purple-grey muted

  /// Soft surface for chip/card background (10% opacity).
  static Color bg(Color c) => c.withOpacity(0.10);
  /// Icon tint (90% opacity).
  static Color icon(Color c) => c.withOpacity(0.90);
}

/// Semantic status colors for chips/badges (success, warning, error, info).
/// Muted, premium tones. Use [bg]/[border]/[fg] for chip rendering.
class SentinelStatusPalette {
  SentinelStatusPalette._();

  static const Color success = Color(0xFF2E7D5E);   // green-ish, muted
  static const Color warning = Color(0xFFB8863C);   // amber, muted
  static const Color error = Color(0xFFA01C2E);     // red, muted
  static const Color info = Color(0xFF5A6B7A);        // blue-grey, neutral

  /// Chip background (10% opacity).
  static Color bg(Color c) => c.withOpacity(0.10);
  /// Chip border (18% opacity).
  static Color border(Color c) => c.withOpacity(0.18);
  /// Chip text/icon (90% opacity).
  static Color fg(Color c) => c.withOpacity(0.90);
}

/// Premium light theme for Sentinel (Material 3).
class SentinelTheme {
  SentinelTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: SentinelColors.bgPrimary,

      colorScheme: const ColorScheme.light(
        primary: SentinelColors.primary,
        secondary: SentinelColors.sentinelAccent,
        surface: SentinelColors.card,
        error: SentinelColors.error,
        onPrimary: Colors.white,
        onSurface: SentinelColors.textPrimary,
        onError: Colors.white,
      ),

      // AppBar – clean & premium
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SentinelColors.textPrimary,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SentinelColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: SentinelColors.textSecondary),
        labelStyle: const TextStyle(color: SentinelColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SentinelColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SentinelColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: SentinelColors.primary,
            width: 1.3,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SentinelColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: SentinelColors.error,
            width: 1.4,
          ),
        ),
      ),

      // ✅ ElevatedButton (fallback safety)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SentinelColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          elevation: 0,
        ),
      ),

      // Primary CTA – FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SentinelColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Cards
      cardTheme: CardTheme(
        color: SentinelColors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: SentinelColors.border),
        ),
      ),

      // Dividers
      dividerTheme: const DividerThemeData(
        color: SentinelColors.border,
        thickness: 1,
      ),

      // Typography (Apple-like, calm)
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: SentinelColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: SentinelColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w400,
          color: SentinelColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: SentinelColors.textSecondary,
        ),
      ),
    );
  }
}
