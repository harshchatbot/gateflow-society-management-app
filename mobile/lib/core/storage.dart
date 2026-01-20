import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const String _keyGuardId = 'guard_id';
  static const String _keyGuardName = 'guard_name';
  static const String _keySocietyId = 'society_id';

  /// Save guard session
  static Future<void> saveGuardSession({
    required String guardId,
    required String guardName,
    required String societyId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGuardId, guardId);
    await prefs.setString(_keyGuardName, guardName);
    await prefs.setString(_keySocietyId, societyId);
  }

  /// Get guard session
  static Future<Map<String, String>?> getGuardSession() async {
    final prefs = await SharedPreferences.getInstance();
    final guardId = prefs.getString(_keyGuardId);
    final guardName = prefs.getString(_keyGuardName);
    final societyId = prefs.getString(_keySocietyId);

    if (guardId == null || guardName == null || societyId == null) {
      return null;
    }

    return {
      'guard_id': guardId,
      'guard_name': guardName,
      'society_id': societyId,
    };
  }

  /// Clear guard session (logout)
  static Future<void> clearGuardSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGuardId);
    await prefs.remove(_keyGuardName);
    await prefs.remove(_keySocietyId);
  }

  /// Check if guard session exists
  static Future<bool> hasGuardSession() async {
    final session = await getGuardSession();
    return session != null;
  }
}
