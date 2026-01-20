import 'package:flutter/material.dart';

class AppTheme {
  // Salesforce-inspired palette
  static const Color primary = Color(0xFF00A1E0);
  static const Color darkBlue = Color(0xFF0176D3);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7FAFC);
  static const Color border = Color(0xFFE5EAF0);
  static const Color textPrimary = Color(0xFF0B1F33);
  static const Color textSecondary = Color(0xFF52606D);
  static const Color success = Color(0xFF2E844A);
  static const Color warning = Color(0xFFFE9339);
  static const Color error = Color(0xFFBA0517);

  // Radii
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: darkBlue,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      background: background,
      onBackground: textPrimary,
      surface: surface,
      onSurface: textPrimary,
      surfaceVariant: surface,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black12,
      scrim: Colors.black54,
      tertiary: success,
      onTertiary: Colors.white,
      inverseSurface: textPrimary,
      inversePrimary: darkBlue,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
      ),
      cardTheme: CardTheme(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: const TextStyle(color: textSecondary),
        labelStyle: const TextStyle(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          backgroundColor: darkBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 16),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
      ),
      dividerColor: border,
    );
  }
}
