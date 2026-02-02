import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const Color accent = Color(0xFF4CAF50); // Limited usage only
  static const Color error = Color(0xFFB11226);

  // UI
  static const Color border = Color(0xFFE6E6E6);
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
        secondary: SentinelColors.accent,
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
