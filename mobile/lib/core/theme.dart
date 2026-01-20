import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // 🎨 NEW Palette (The "Salesforce/Facebook" Look)
  static const Color primaryBlue = Color(0xFF0176D3); 
  static const Color backgroundGrey = Color(0xFFF5F7FA);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF181B25);    
  static const Color textGrey = Color(0xFF5E6C84);    
  static const Color borderGrey = Color(0xFFDFE1E6);  
  static const Color errorRed = Color(0xFFBA0517);
  static const Color successGreen = Color(0xFF2E844A);

  // 🛠 BACKWARDS COMPATIBILITY (Restoring missing variables for your widgets)
  static const Color primary = primaryBlue;       // Map 'primary' to new blue
  static const Color darkBlue = primaryBlue;      // Map 'darkBlue' to new blue
  static const Color textPrimary = textDark;      // Map 'textPrimary' to new dark text
  static const double radiusMd = 12.0;            // Restore radiusMd
  static const double radiusLg = 16.0;            // Restore radiusLg

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundGrey, 
      
      // Color Scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: primaryBlue,
        background: backgroundGrey,
        surface: surfaceWhite,
        error: errorRed,
        brightness: Brightness.light,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: surfaceWhite,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: textGrey),
        prefixIconColor: textGrey,
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Text
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: textDark, fontWeight: FontWeight.w700, fontSize: 26),
        titleMedium: TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 18),
        bodyMedium: TextStyle(color: textDark, fontSize: 16),
        bodySmall: TextStyle(color: textGrey, fontSize: 14),
      ),
    );
  }
}