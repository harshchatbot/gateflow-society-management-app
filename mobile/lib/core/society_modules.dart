import '../services/firestore_service.dart';

/// Module IDs used in society document `modules` map.
/// Enable/disable per society via DB; missing or true = enabled.
class SocietyModuleIds {
  SocietyModuleIds._();

  static const String visitorManagement = 'visitor_management';
  static const String complaints = 'complaints';
  static const String notices = 'notices';
  static const String violations = 'violations';
  static const String sos = 'sos';

  /// All known module IDs (for defaults when society has no modules map).
  static const List<String> all = [
    visitorManagement,
    complaints,
    notices,
    violations,
    sos,
  ];
}

/// Society-level feature flags (modules). Controlled via DB only; no UI toggles.
/// Cache is loaded when user enters a shell (splash preloads); clear on sign out.
class SocietyModules {
  SocietyModules._();

  static String? _cachedSocietyId;
  static Map<String, bool> _cachedModules = {};

  static final FirestoreService _firestore = FirestoreService();

  /// Load society doc and cache modules for [societyId]. Call before showing dashboards.
  /// If society has no `modules` field, all modules are treated as enabled (backward compatible).
  static Future<void> ensureLoaded(String societyId) async {
    if (societyId.isEmpty) {
      _cachedSocietyId = null;
      _cachedModules = {};
      return;
    }
    if (_cachedSocietyId == societyId && _cachedModules.isNotEmpty) return;

    try {
      final data = await _firestore.getSociety(societyId);
      _cachedSocietyId = societyId;
      final raw = data?['modules'];
      if (raw is Map) {
        final map = raw as Map;
        for (final id in SocietyModuleIds.all) {
          final v = map[id];
          _cachedModules[id] = (v != false);
        }
      } else {
        for (final id in SocietyModuleIds.all) {
          _cachedModules[id] = true;
        }
      }
    } catch (_) {
      _cachedSocietyId = societyId;
      for (final id in SocietyModuleIds.all) {
        _cachedModules[id] = true;
      }
    }
  }

  /// Whether the given module is enabled for the current society.
  /// Returns true if not yet loaded or module key missing (safe default).
  static bool isEnabled(String moduleId) {
    return _cachedModules[moduleId] ?? true;
  }

  /// Clear cache (call on sign out).
  static void clear() {
    _cachedSocietyId = null;
    _cachedModules = {};
  }
}
