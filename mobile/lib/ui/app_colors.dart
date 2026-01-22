import 'package:flutter/material.dart';

class AppColors {
  // Apple/Google premium light palette
  static const Color primary = Color(0xFF2563EB); // blue
  static const Color primarySoft = Color(0xFFDBEAFE);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  
  // Admin theme (purple/violet)
  static const Color admin = Color(0xFF8B5CF6); // Purple
  static const Color adminSoft = Color(0xFFEDE9FE);

  static const Color bg = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E7EB);

  static const Color text = Color(0xFF111827);
  static const Color text2 = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  static Color statusChipBg(String status) {
    switch (status.toUpperCase()) {
      case "APPROVED":
        return success.withOpacity(0.12);
      case "REJECTED":
        return error.withOpacity(0.12);
      case "PENDING":
      default:
        return warning.withOpacity(0.14);
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
