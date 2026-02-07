import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

import 'firebase_auth_service.dart';

/// Firestore-first resident favorites + local auto-approve preferences.
///
/// Firestore model:
/// societies/{societyId}/units/{unitId}/favorite_visitors/{visitorKey}
///
/// Local-only (SharedPreferences):
/// - auto-approve flag: bool
/// - auto-approved-once map: {pendingId: timestampMs} with TTL pruning
class FavoriteVisitorsService {
  FavoriteVisitorsService._internal();
  static final FavoriteVisitorsService instance =
      FavoriteVisitorsService._internal();

  static const _autoApprovePrefix = 'fav_auto_approve_v1';
  static const _autoApprovedOncePrefix = 'fav_auto_approved_once_v1';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 24 hours in milliseconds for de-dupe TTL
  static const int _autoApprovedTtlMs = 24 * 60 * 60 * 1000;

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

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

  static String _normalizePurpose(String? purpose) {
    final raw = purpose ?? '';
    return raw.trim().toLowerCase();
  }

  static String? _normalizePhoneOrNull(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    final normalized = FirebaseAuthService.normalizePhoneForIndia(phone);
    final digits = normalized.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return null;
    return normalized;
  }

  static String _hashNamePurpose({
    required String name,
    required String? purpose,
  }) {
    final payload = '${normalizeName(name)}|${_normalizePurpose(purpose)}';
    return sha1.convert(utf8.encode(payload)).toString();
  }

  /// visitorKey rules:
  /// - phone exists => phone_<E164>
  /// - otherwise => hash_<sha1(lower(name.trim()) + "|" + lower(purpose.trim()))>
  static String buildVisitorKey({
    required String name,
    String? phone,
    String? purpose,
  }) {
    final normalizedPhone = _normalizePhoneOrNull(phone);
    if (normalizedPhone != null) return 'phone_$normalizedPhone';
    return 'hash_${_hashNamePurpose(name: name, purpose: purpose)}';
  }

  CollectionReference<Map<String, dynamic>> _favoritesRef({
    required String societyId,
    required String unitId,
  }) {
    return _firestore
        .collection('societies')
        .doc(societyId)
        .collection('units')
        .doc(unitId)
        .collection('favorite_visitors');
  }

  CollectionReference<Map<String, dynamic>> _legacyFavoritesRef({
    required String societyId,
    required String unitId,
  }) {
    return _firestore
        .collection('societies')
        .doc(societyId)
        .collection('flats')
        .doc(unitId)
        .collection('favorite_visitors');
  }

  /// Firestore-first read of normalized favorite names for a unit.
  /// [residentId] is retained for API compatibility.
  Future<Set<String>> getFavorites(
    String societyId,
    String residentId, {
    String? unitId,
    int limit = 200,
  }) async {
    final resolvedUnit = (unitId ?? '').trim();
    if (resolvedUnit.isEmpty) return <String>{};

    try {
      final snap = await _favoritesRef(societyId: societyId, unitId: resolvedUnit)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => (d.data()['name'] ?? '').toString())
          .where((name) => name.trim().isNotEmpty)
          .map(normalizeName)
          .toSet();
    } catch (_) {
      // Compatibility fallback: read old Firestore path if present.
      try {
        final legacy = await _legacyFavoritesRef(
          societyId: societyId,
          unitId: resolvedUnit,
        ).limit(limit).get();
        return legacy.docs
            .map((d) => (d.data()['name'] ?? '').toString())
            .where((name) => name.trim().isNotEmpty)
            .map(normalizeName)
            .toSet();
      } catch (_) {
        return <String>{};
      }
    }
  }

  /// Check if [name] (raw) is in [favorites] using normalization.
  bool isFavorite(String name, Set<String> favorites) {
    final norm = normalizeName(name);
    return favorites.contains(norm);
  }

  /// Toggle favorite in Firestore for [visitorName]. Returns updated favorites set.
  /// [residentId] is retained for API compatibility.
  Future<Set<String>> toggleFavorite({
    required String societyId,
    required String residentId,
    required String visitorName,
    String? visitorPhone,
    String? purpose,
    String? photoUrl,
    String? unitId,
  }) async {
    final resolvedUnitId = (unitId ?? '').trim();
    if (resolvedUnitId.isEmpty) return <String>{};

    final normalizedName = visitorName.trim();
    final normalizedPhone = _normalizePhoneOrNull(visitorPhone);
    final normalizedPurpose = (purpose ?? '').trim();
    final key = buildVisitorKey(
      name: normalizedName.isEmpty ? (normalizedPhone ?? 'visitor') : normalizedName,
      phone: normalizedPhone,
      purpose: normalizedPurpose,
    );

    final ref = _favoritesRef(societyId: societyId, unitId: resolvedUnitId).doc(key);
    final existing = await ref.get();

    if (existing.exists) {
      await ref.delete();
    } else {
      await ref.set({
        'name': normalizedName.isNotEmpty ? normalizedName : (normalizedPhone ?? 'Visitor'),
        'phone': normalizedPhone,
        'purpose': normalizedPurpose.isEmpty ? null : normalizedPurpose,
        'photoUrl': (photoUrl == null || photoUrl.trim().isEmpty) ? null : photoUrl.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': _auth.currentUser?.uid ?? residentId,
      });
    }

    return getFavorites(
      societyId,
      residentId,
      unitId: resolvedUnitId,
    );
  }

  Future<bool> isFavoriteVisitor({
    required String societyId,
    required String unitId,
    required String visitorKey,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty || visitorKey.trim().isEmpty) return false;

    // Preferred path
    final primary = await _favoritesRef(
      societyId: societyId,
      unitId: resolvedUnit,
    ).doc(visitorKey).get();
    if (primary.exists) return true;

    // Compatibility fallback path
    final legacy = await _legacyFavoritesRef(
      societyId: societyId,
      unitId: resolvedUnit,
    ).doc(visitorKey).get();
    return legacy.exists;
  }

  Future<List<Map<String, dynamic>>> getFavoriteVisitorsForUnit({
    required String societyId,
    required String unitId,
    int limit = 5,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty) return <Map<String, dynamic>>[];

    try {
      final snap = await _favoritesRef(
        societyId: societyId,
        unitId: resolvedUnit,
      ).orderBy('createdAt', descending: true).limit(limit).get();

      final mapped = snap.docs.map((d) {
        final data = d.data();
        return <String, dynamic>{
          'visitorKey': d.id,
          'name': (data['name'] ?? '').toString(),
          'phone': data['phone']?.toString(),
          'purpose': data['purpose']?.toString(),
          'photoUrl': data['photoUrl']?.toString(),
        };
      }).where((m) => (m['name'] as String).trim().isNotEmpty).toList();

      if (mapped.isNotEmpty) return mapped;
    } catch (_) {
      // continue to compatibility fallback
    }

    try {
      final legacy = await _legacyFavoritesRef(
        societyId: societyId,
        unitId: resolvedUnit,
      ).limit(limit).get();
      return legacy.docs.map((d) {
        final data = d.data();
        return <String, dynamic>{
          'visitorKey': d.id,
          'name': (data['name'] ?? '').toString(),
          'phone': data['phone']?.toString(),
          'purpose': data['purpose']?.toString(),
          'photoUrl': data['photoUrl']?.toString(),
        };
      }).where((m) => (m['name'] as String).trim().isNotEmpty).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
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
