import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';

/// Keys for caching quote in SharedPreferences.
const String _keyQuoteDate = 'quote_date';
const String _keyQuoteText = 'quote_text';

/// Default placeholder shown while quote is loading.
const String kPlaceholderQuote = 'Welcome. Stay secure.';

/// Firestore collection for admin-managed daily quotes.
const String _collectionDailyQuotes = 'daily_quotes';

/// Returns today's date key in local timezone (YYYY-MM-DD).
String _todayKey() {
  final now = DateTime.now();
  final y = now.year;
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Stable hash of a string for deterministic quote index (same day → same quote).
int _stableHash(String s) {
  int h = 0;
  for (int i = 0; i < s.length; i++) {
    h = 0x1fffffff & (h + s.codeUnitAt(i));
    h = 0x1fffffff & (h + ((h << 10) & 0xFFFFFFFF));
    h ^= (h >> 6);
  }
  h = 0x1fffffff & (h + ((h << 3) & 0xFFFFFFFF));
  h ^= (h >> 11);
  return 0x1fffffff & (h + ((h << 15) & 0xFFFFFFFF));
}

/// Fallback quotes used when Firestore is unavailable or returns no data.
const List<String> _fallbackQuotes = [
  'Safety first. Stay vigilant.',
  'Welcome. Stay secure.',
  'Your community, your security.',
  'One tap to secure your gate.',
  'Peace of mind starts at the gate.',
  'Together we keep our society safe.',
  'Smart living, secure living.',
  'Trust the process. Stay secure.',
  'Every visitor accounted for.',
  'Security made simple.',
  'Your society, guarded with care.',
  'Stay alert. Stay safe.',
  'Gate secure, mind at ease.',
  'Community first, safety always.',
  'Welcome home. You\'re secure.',
  'One society, one standard.',
  'Secure today, peaceful tomorrow.',
  'Guard what matters.',
  'Safety in every tap.',
  'Sentinel has your back.',
  'Secure gates, happy residents.',
  'Trust Sentinel for your society.',
  'Stay safe. Stay connected.',
  'Your gate, your rules.',
  'Security that fits your life.',
];

/// Service for "Quote of the Day": cached per day, optional Firestore, offline fallback.
class QuoteService {
  QuoteService({
    SharedPreferences? prefs,
    FirebaseFirestore? firestore,
  })  : _prefs = prefs,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final SharedPreferences? _prefs;
  final FirebaseFirestore _firestore;

  /// Returns the quote of the day. Uses cache if same day; otherwise fetches
  /// from Firestore (if available) or fallback list, then caches.
  Future<String> getQuoteOfTheDay() async {
    final todayKey = _todayKey();
    final prefs = _prefs ?? await SharedPreferences.getInstance();

    final storedDate = prefs.getString(_keyQuoteDate);
    final storedQuote = prefs.getString(_keyQuoteText);
    if (storedDate == todayKey && storedQuote != null && storedQuote.isNotEmpty) {
      return storedQuote;
    }

    String quote = kPlaceholderQuote;
    try {
      final fromFirestore = await _fetchQuotesFromFirestore();
      if (fromFirestore.isNotEmpty) {
        final index = _stableHash(todayKey).abs() % fromFirestore.length;
        quote = fromFirestore[index];
      } else {
        final index = _stableHash(todayKey).abs() % _fallbackQuotes.length;
        quote = _fallbackQuotes[index];
      }
    } catch (e, st) {
      AppLogger.w('Quote of the day: Firestore failed, using fallback', error: e, stackTrace: st);
      final index = _stableHash(todayKey).abs() % _fallbackQuotes.length;
      quote = _fallbackQuotes[index];
    }

    await prefs.setString(_keyQuoteDate, todayKey);
    await prefs.setString(_keyQuoteText, quote);
    return quote;
  }

  /// Fetches active quotes from Firestore. Returns empty list on error or no data.
  Future<List<String>> _fetchQuotesFromFirestore() async {
    try {
      final snapshot = await _firestore
          .collection(_collectionDailyQuotes)
          .where('active', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 5));

      final quotes = <String>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final text = data['text']?.toString()?.trim();
        if (text == null || text.isEmpty) continue;
        final lang = data['lang']?.toString()?.toLowerCase();
        if (lang != null && lang.isNotEmpty && lang != 'en') continue;
        quotes.add(text);
      }
      if (quotes.isNotEmpty) {
        AppLogger.i('Quote of the day: loaded ${quotes.length} from Firestore');
      }
      return quotes;
    } catch (e) {
      rethrow;
    }
  }
}
