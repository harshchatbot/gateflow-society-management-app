import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only resident favorites + auto-approve management.
/// Tenant-safe (societyId + residentId) and schema-free.
///
/// Stores:
/// - favorites: List<String> of NORMALIZED names
/// - auto-approve flag: bool
/// - auto-approved-once map: {pendingId: timestampMs} with TTL pruning
class FavoriteVisitorsService {
  FavoriteVisitorsService._internal();
  static final FavoriteVisitorsService instance = FavoriteVisitorsService._internal();

  static const _favoritesPrefix = 'fav_visitors_v1';
  static const _autoApprovePrefix = 'fav_auto_approve_v1';
  static const _autoApprovedOncePrefix = 'fav_auto_approved_once_v1';

  // 24 hours in milliseconds for de-dupe TTL
  static const int _autoApprovedTtlMs = 24 * 60 * 60 * 1000;

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String _favoritesKey(String societyId, String residentId) =>
      '$_favoritesPrefix:${societyId}_$residentId';

  String _autoApproveKey(String societyId, String residentId) =>
      '$_autoApprovePrefix:${societyId}_$residentId';

  String _autoApprovedOnceKey(String societyId, String residentId) =>
      '$_autoApprovedOncePrefix:${societyId}_$residentId';

  /// Normalize a display name for stable matching:
  /// - trim
  /// - lowercase
  /// - collapse multiple spaces
  static String normalizeName(String name) {
    final trimmed = name.trim().toLowerCase();
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Load favorites as a normalized Set of names.
  Future<Set<String>> getFavorites(String societyId, String residentId) async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_favoritesKey(societyId, residentId)) ?? const [];
    // IMPORTANT: enforce normalization on read (fixes legacy saved values)
    return raw.map((e) => normalizeName(e)).toSet();
  }

  /// Check if [name] (raw) is in [favorites] using normalization.
  bool isFavorite(String name, Set<String> favorites) {
    final norm = normalizeName(name);
    return favorites.contains(norm);
  }

  /// Toggle favorite for [visitorName]. Returns updated favorites set.
  Future<Set<String>> toggleFavorite({
    required String societyId,
    required String residentId,
    required String visitorName,
  }) async {
    final prefs = await _prefs;
    final key = _favoritesKey(societyId, residentId);
    final existingRaw = prefs.getStringList(key) ?? const [];
    final existing = existingRaw.map((e) => normalizeName(e)).toSet();

    final norm = normalizeName(visitorName);
    if (existing.contains(norm)) {
      existing.remove(norm);
    } else {
      existing.add(norm);
    }

    await prefs.setStringList(key, existing.toList());
    return existing;
  }

  /// Whether auto-approve for favorites is enabled for this tenant.
  Future<bool> getAutoApproveEnabled(String societyId, String residentId) async {
    final prefs = await _prefs;
    return prefs.getBool(_autoApproveKey(societyId, residentId)) ?? false;
  }

  Future<void> setAutoApproveEnabled(
    String societyId,
    String residentId,
    bool enabled,
  ) async {
    final prefs = await _prefs;
    await prefs.setBool(_autoApproveKey(societyId, residentId), enabled);
  }

  /// Internal: load + prune auto-approved map (pendingId -> timestamp).
  Future<Map<String, int>> _loadAutoApprovedMap(
    String societyId,
    String residentId,
  ) async {
    final prefs = await _prefs;
    final key = _autoApprovedOnceKey(societyId, residentId);
    final raw = prefs.getString(key);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      final Map<String, int> result = {};
      decoded.forEach((k, v) {
        if (k is! String) return;
        final ts = v is int ? v : int.tryParse(v.toString());
        if (ts == null) return;

        // TTL prune
        if (now - ts <= _autoApprovedTtlMs) {
          result[k] = ts;
        }
      });

      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAutoApprovedMap(
    String societyId,
    String residentId,
    Map<String, int> map,
  ) async {
    final prefs = await _prefs;
    final key = _autoApprovedOnceKey(societyId, residentId);

    if (map.isEmpty) {
      await prefs.remove(key);
      return;
    }

    await prefs.setString(key, jsonEncode(map));
  }

  /// Mark a pending approval as auto-approved once (with TTL).
  Future<void> markAutoApprovedOnce({
    required String societyId,
    required String residentId,
    required String pendingId,
  }) async {
    final map = await _loadAutoApprovedMap(societyId, residentId);
    map[pendingId] = DateTime.now().millisecondsSinceEpoch;
    await _saveAutoApprovedMap(societyId, residentId, map);
  }

  /// Returns true if this pendingId was auto-approved within TTL.
  Future<bool> wasAutoApproved({
    required String societyId,
    required String residentId,
    required String pendingId,
  }) async {
    final map = await _loadAutoApprovedMap(societyId, residentId);
    return map.containsKey(pendingId);
  }
}
