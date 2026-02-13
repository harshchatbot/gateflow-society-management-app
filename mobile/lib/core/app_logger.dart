import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logger for the app.
/// Uses pretty logging in debug; can be silenced in release.
class AppLogger {
  static final Logger _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.debug,
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.none,
    ),
  );

  static void d(String message, {Map<String, dynamic>? data}) {
    _logger.d(_format(message, data));
  }

  static void i(String message, {Map<String, dynamic>? data}) {
    _logger.i(_format(message, data));
  }

  static void w(String message,
      {Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    _logger.w(_format(message, data), error: error, stackTrace: stackTrace);
  }

  static void e(String message,
      {Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    _logger.e(_format(message, data), error: error, stackTrace: stackTrace);
  }

  static String _format(String message, Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return message;
    return '$message | $data';
  }
}
