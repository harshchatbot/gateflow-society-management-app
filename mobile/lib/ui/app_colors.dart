import 'package:flutter/material.dart';

class AppColors {
  // Apple/Google premium light palette
  static const Color primary = Color(0xFF8D5E3C); // warm brown
  static const Color primarySoft = Color(0xFFF1E4D7);

  static const Color success = Color(0xFF6E8A5E);
  static const Color warning = Color(0xFFC58A3A);
  static const Color error = Color(0xFFB85A49);

  // Admin theme (purple/violet)
  static const Color admin = Color(0xFF5B3B28); // deep espresso brown
  static const Color adminSoft = Color(0xFFF3E7DA);

  static const Color bg = Color(0xFFF6F1EA);
  static const Color surface = Color(0xFFFFFCF8);
  static const Color border = Color(0xFFE6D8C9);

  static const Color text = Color(0xFF2A1F18);
  static const Color text2 = Color(0xFF7D6B5B);
  static const Color textMuted = Color(0xFFA08E80);

  static Color statusChipBg(String status) {
    switch (status.toUpperCase()) {
      case "APPROVED":
        return success.withValues(alpha: 0.12);
      case "REJECTED":
        return error.withValues(alpha: 0.12);
      case "PENDING":
      default:
        return warning.withValues(alpha: 0.14);
    }
  }

  static Color statusChipFg(String status) {
    switch (status.toUpperCase()) {
      case "APPROVED":
        return success;
      case "REJECTED":
        return error;
      case "PENDING":
      default:
        return warning;
    }
  }
}
