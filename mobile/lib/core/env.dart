import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static Future<void> load() async {
    try {
      debugPrint('🔧 Loading .env file...');
      await dotenv.load(fileName: '.env');
      debugPrint('✅ .env loaded');
      debugPrint('🌐 API_BASE_URL from .env = ${dotenv.env['API_BASE_URL']}');
    } catch (e) {
      debugPrint('❌ Failed to load .env: $e');
      rethrow;
    }
  }

  static String get apiBaseUrl {
    final url = dotenv.env['API_BASE_URL'];
    if (url == null || url.isEmpty) {
      debugPrint('❌ API_BASE_URL missing in .env');
      // Fail fast so you *know* it's config, not networking.
      return '';
    }
    return url;
  }
}
