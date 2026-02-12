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

  DocumentReference<Map<String, dynamic>> _unitVisitorSettingsRef({
    required String societyId,
    required String unitId,
  }) {
    return _firestore
        .collection('societies')
        .doc(societyId)
        .collection('units')
        .doc(unitId)
        .collection('settings')
        .doc('visitor_access');
  }

  CollectionReference<Map<String, dynamic>> _unitPreapprovalsRef({
    required String societyId,
    required String unitId,
  }) {
    return _firestore
        .collection('societies')
        .doc(societyId)
        .collection('units')
        .doc(unitId)
        .collection('preapprovals');
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
        'visitorKey': key,
        'isPreApproved': false,
        'notifyResidentOnEntry': true,
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
          'isPreApproved': data['isPreApproved'] == true,
          'notifyResidentOnEntry': data['notifyResidentOnEntry'] != false,
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
          'isPreApproved': data['isPreApproved'] == true,
          'notifyResidentOnEntry': data['notifyResidentOnEntry'] != false,
        };
      }).where((m) => (m['name'] as String).trim().isNotEmpty).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Whether auto-approve for favorites is enabled for this tenant.
  Future<bool> getAutoApproveEnabled(
    String societyId,
    String residentId, {
    String? unitId,
  }) async {
    final resolvedUnit = (unitId ?? '').trim();
    if (resolvedUnit.isNotEmpty) {
      try {
        final snap = await _unitVisitorSettingsRef(
          societyId: societyId,
          unitId: resolvedUnit,
        ).get();
        final data = snap.data();
        if (data != null && data['autoApproveFavouritesEnabled'] is bool) {
          return data['autoApproveFavouritesEnabled'] == true;
        }
      } catch (_) {
        // fall back to local setting for backward compatibility
      }
    }
    final prefs = await _prefs;
    return prefs.getBool(_autoApproveKey(societyId, residentId)) ?? false;
  }

  Future<void> setAutoApproveEnabled(
    String societyId,
    String residentId,
    bool enabled,
    {
    String? unitId,
  }) async {
    final resolvedUnit = (unitId ?? '').trim();
    if (resolvedUnit.isNotEmpty) {
      try {
        await _unitVisitorSettingsRef(
          societyId: societyId,
          unitId: resolvedUnit,
        ).set({
          'autoApproveFavouritesEnabled': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': _auth.currentUser?.uid ?? residentId,
        }, SetOptions(merge: true));
      } catch (_) {
        // keep local fallback write below
      }
    }
    final prefs = await _prefs;
    await prefs.setBool(_autoApproveKey(societyId, residentId), enabled);
  }

  Future<void> updateFavoriteSettings({
    required String societyId,
    required String unitId,
    required String visitorKey,
    bool? isPreApproved,
    bool? notifyResidentOnEntry,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': _auth.currentUser?.uid,
    };
    if (isPreApproved != null) updates['isPreApproved'] = isPreApproved;
    if (notifyResidentOnEntry != null) {
      updates['notifyResidentOnEntry'] = notifyResidentOnEntry;
    }
    await _favoritesRef(
      societyId: societyId,
      unitId: unitId,
    ).doc(visitorKey).set(updates, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> findMatchingFavorite({
    required String societyId,
    required String unitId,
    required String name,
    String? phone,
    String? purpose,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty) return null;
    final trimmedName = name.trim();
    final trimmedPhone = (phone ?? '').trim();
    if (trimmedName.isEmpty && trimmedPhone.isEmpty) return null;

    final key = buildVisitorKey(
      name: trimmedName.isEmpty ? trimmedPhone : trimmedName,
      phone: trimmedPhone,
      purpose: purpose,
    );
    final doc = await _favoritesRef(
      societyId: societyId,
      unitId: resolvedUnit,
    ).doc(key).get();
    if (doc.exists) {
      final data = doc.data() ?? <String, dynamic>{};
      return <String, dynamic>{
        'id': doc.id,
        'visitorKey': key,
        'name': (data['name'] ?? '').toString(),
        'phone': data['phone']?.toString(),
        'purpose': data['purpose']?.toString(),
        'isPreApproved': data['isPreApproved'] == true,
        'notifyResidentOnEntry': data['notifyResidentOnEntry'] != false,
      };
    }

    // Compatibility fallback by normalized name from legacy docs.
    final normalized = normalizeName(trimmedName);
    if (normalized.isEmpty) return null;
    try {
      final legacy = await _legacyFavoritesRef(
        societyId: societyId,
        unitId: resolvedUnit,
      ).limit(200).get();
      for (final d in legacy.docs) {
        final data = d.data();
        final candidate = normalizeName((data['name'] ?? '').toString());
        if (candidate == normalized) {
          return <String, dynamic>{
            'id': d.id,
            'visitorKey': d.id,
            'name': (data['name'] ?? '').toString(),
            'phone': data['phone']?.toString(),
            'purpose': data['purpose']?.toString(),
            'isPreApproved': data['isPreApproved'] == true,
            'notifyResidentOnEntry': data['notifyResidentOnEntry'] != false,
          };
        }
      }
    } catch (_) {
      // ignore fallback failures
    }
    return null;
  }

  Future<Map<String, dynamic>?> findActivePreapproval({
    required String societyId,
    required String unitId,
    required String visitorKey,
    required DateTime now,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty || visitorKey.trim().isEmpty) return null;
    try {
      final snap = await _unitPreapprovalsRef(
        societyId: societyId,
        unitId: resolvedUnit,
      ).get();
      final weekday = now.weekday;
      final nowMinutes = now.hour * 60 + now.minute;
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['visitorKey'] ?? '').toString().trim() != visitorKey) continue;
        final validFromTs = data['validFrom'];
        final validToTs = data['validTo'];
        if (validFromTs is! Timestamp || validToTs is! Timestamp) continue;
        final validFrom = validFromTs.toDate();
        final validTo = validToTs.toDate();
        if (now.isBefore(validFrom) || now.isAfter(validTo)) continue;

        final days = data['daysOfWeek'];
        if (days is List && days.isNotEmpty) {
          final parsedDays = days.map((e) => int.tryParse(e.toString())).whereType<int>().toSet();
          if (!parsedDays.contains(weekday)) continue;
        }

        final fromMins = int.tryParse((data['timeFromMins'] ?? '').toString());
        final toMins = int.tryParse((data['timeToMins'] ?? '').toString());
        if (fromMins != null && toMins != null) {
          if (nowMinutes < fromMins || nowMinutes > toMins) continue;
        }

        final maxEntries = int.tryParse((data['maxEntries'] ?? '').toString());
        final usedEntries = int.tryParse((data['usedEntries'] ?? '').toString()) ?? 0;
        if (maxEntries != null && usedEntries >= maxEntries) continue;

        return <String, dynamic>{
          'id': d.id,
          'notifyResidentOnEntry': data['notifyResidentOnEntry'] != false,
        };
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getPreapprovalsForUnit({
    required String societyId,
    required String unitId,
    int limit = 100,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty) return <Map<String, dynamic>>[];
    try {
      final snap = await _unitPreapprovalsRef(
        societyId: societyId,
        unitId: resolvedUnit,
      ).limit(limit).get();
      return snap.docs.map((d) {
        final data = d.data();
        final validFromTs = data['validFrom'];
        final validToTs = data['validTo'];
        return <String, dynamic>{
          'id': d.id,
          'visitorKey': (data['visitorKey'] ?? '').toString(),
          'validFrom': validFromTs is Timestamp ? validFromTs.toDate() : null,
          'validTo': validToTs is Timestamp ? validToTs.toDate() : null,
          'daysOfWeek': (data['daysOfWeek'] is List)
              ? (data['daysOfWeek'] as List)
                  .map((e) => int.tryParse(e.toString()))
                  .whereType<int>()
                  .toList()
              : <int>[],
          'timeFromMins': int.tryParse((data['timeFromMins'] ?? '').toString()),
          'timeToMins': int.tryParse((data['timeToMins'] ?? '').toString()),
          'maxEntries': int.tryParse((data['maxEntries'] ?? '').toString()),
          'usedEntries': int.tryParse((data['usedEntries'] ?? '').toString()) ?? 0,
          'notifyResidentOnEntry': data['notifyResidentOnEntry'] != false,
        };
      }).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> upsertPreapproval({
    required String societyId,
    required String unitId,
    String? preapprovalId,
    required String visitorKey,
    required DateTime validFrom,
    required DateTime validTo,
    List<int>? daysOfWeek,
    int? timeFromMins,
    int? timeToMins,
    int? maxEntries,
    bool notifyResidentOnEntry = true,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty || visitorKey.trim().isEmpty) return;
    final doc = (preapprovalId == null || preapprovalId.trim().isEmpty)
        ? _unitPreapprovalsRef(societyId: societyId, unitId: resolvedUnit).doc()
        : _unitPreapprovalsRef(
            societyId: societyId,
            unitId: resolvedUnit,
          ).doc(preapprovalId.trim());
    final payload = <String, dynamic>{
      'visitorKey': visitorKey.trim(),
      'validFrom': Timestamp.fromDate(validFrom),
      'validTo': Timestamp.fromDate(validTo),
      'daysOfWeek': (daysOfWeek ?? <int>[]),
      'timeFromMins': timeFromMins,
      'timeToMins': timeToMins,
      'maxEntries': maxEntries,
      'notifyResidentOnEntry': notifyResidentOnEntry,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': _auth.currentUser?.uid,
      'usedEntries': 0,
    };
    payload.removeWhere((key, value) => value == null);
    if (preapprovalId == null || preapprovalId.trim().isEmpty) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdByUid'] = _auth.currentUser?.uid;
    }
    await doc.set(payload, SetOptions(merge: true));
  }

  Future<void> deletePreapproval({
    required String societyId,
    required String unitId,
    required String preapprovalId,
  }) async {
    final resolvedUnit = unitId.trim();
    if (resolvedUnit.isEmpty || preapprovalId.trim().isEmpty) return;
    await _unitPreapprovalsRef(
      societyId: societyId,
      unitId: resolvedUnit,
    ).doc(preapprovalId.trim()).delete();
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
