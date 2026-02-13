import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_logger.dart';
import 'app_error.dart';

class Env {
  static Future<void> load() async {
    try {
      AppLogger.i('Loading .env file...');
      await dotenv.load(fileName: 'assets/.env');
      // Do not log actual env values to avoid leaking configuration in logs
      AppLogger.i('Env loaded');
    } catch (e, st) {
      AppLogger.e('Failed to load .env', error: e, stackTrace: st);
      throw AppError(
        userMessage:
            'Configuration error. Please reinstall or contact support.',
        technicalMessage: 'Env load failed: $e',
      );
    }
  }

  static String get apiBaseUrl {
    final url = dotenv.env['API_BASE_URL'];
    if (url == null || url.isEmpty) {
      AppLogger.e('API_BASE_URL missing in .env');
      return '';
    }
    return url;
  }
}
