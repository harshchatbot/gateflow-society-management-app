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
  static const Color bgPrimary = Color(0xFFF7F7F8);
  static const Color card = Colors.white;

  // Text
  static const Color textPrimary = Color(0xFF1D1D1F);
  static const Color textSecondary = Color(0xFF6E6E73);

  // Brand (premium neutral-first)
  static const Color primary = Color(0xFF3A3A3C);      // Graphite
  static const Color primaryDark = Color(0xFF2C2C2E);  // Deeper graphite
  static const Color error = Color(0xFFB64A42);        // Muted red

  // Accent family (subtle amber/green)
  static const Color yellow = Color(0xFFD4A83E);
  static const Color amber = Color(0xFFC98A2E);
  static const Color sentinelAccent = amber;
  static const Color success = Color(0xFF3E8E63);      // muted green
  static const Color redSoft = Color(0xFFF8ECEB);
  static const Color successSoft = Color(0xFFEDF6F0);
  static Color get sentinelAccentSurface => sentinelAccent.withOpacity(0.04);
  static Color get sentinelAccentBorder => sentinelAccent.withOpacity(0.06);

  /// Canonical accent for resident UI. Use theme.colorScheme.primary for admin/guard.
  static Color get accent => sentinelAccent;
  /// Optional opacity (default 0.04). For surfaces/tints.
  static Color accentSurface([double opacity = 0.04]) => sentinelAccent.withOpacity(opacity);
  /// Border tint for accent areas.
  static Color get accentBorder => sentinelAccentBorder;

  // UI borders: use theme.dividerColor in widgets (neutralBorder). Fallback:
  static const Color border = Color(0xFFE5E5EA);
}

/// Notice board category colors (Event / Alert / Maintenance / Policy).
/// Muted, premium tones. Use [bg] for chip/card backgrounds, [icon] for icon tint.
class NoticeCategoryPalette {
  NoticeCategoryPalette._();

  static const Color event = Color(0xFF4D8E6E);       // muted green
  static const Color alert = Color(0xFFC98A2E);       // muted amber
  static const Color maintenance = Color(0xFF7A7A80); // soft grey
  static const Color policy = Color(0xFF55555B);      // deep neutral

  /// Soft surface for chip/card background (10% opacity).
  static Color bg(Color c) => c.withOpacity(0.10);
  /// Icon tint (90% opacity).
  static Color icon(Color c) => c.withOpacity(0.90);
}

/// Semantic status colors for chips/badges (success, warning, error, info).
/// Muted, premium tones. Use [bg]/[border]/[fg] for chip rendering.
class SentinelStatusPalette {
  SentinelStatusPalette._();

  static const Color success = Color(0xFF3E8E63);   // muted green
  static const Color warning = Color(0xFFC98A2E);   // muted amber
  static const Color error = Color(0xFFB64A42);     // muted red
  static const Color info = Color(0xFF7A7A80);      // neutral grey

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
        tertiary: SentinelColors.success,
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
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return SentinelColors.primary.withOpacity(0.45);
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return SentinelColors.primaryDark;
            }
            return SentinelColors.primary;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          elevation: WidgetStateProperty.all(0),
        ),
      ),

      // Primary CTA – FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return SentinelColors.primary.withOpacity(0.45);
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return SentinelColors.primaryDark;
            }
            return SentinelColors.primary;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
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
