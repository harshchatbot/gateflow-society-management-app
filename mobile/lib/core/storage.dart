import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GuardSession {
  final String guardId;
  final String guardName;
  final String societyId;

  GuardSession({
    required this.guardId,
    required this.guardName,
    required this.societyId,
  });
}

class ResidentSession {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;

  ResidentSession({
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
  });
}

class AdminSession {
  final String adminId;
  final String adminName;
  final String societyId;

  /// Society role (PRESIDENT/SECRETARY/TREASURER/ADMIN/etc.)
  final String role;

  /// System role (admin | super_admin)
  final String systemRole;

  AdminSession({
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.role,
    required this.systemRole,
  });
}

class Storage {
  // Secure storage instance for sensitive identity/session data
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Keys
  static const String _kGuardId = "guard_id";
  static const String _kGuardName = "guard_name";
  static const String _kGuardSocietyId = "guard_society_id";

  static const String _kResidentId = "resident_id";
  static const String _kResidentName = "resident_name";
  static const String _kResidentSocietyId = "resident_society_id";
  static const String _kResidentFlatNo = "resident_flat_no";

  static const String _kAdminId = "admin_id";
  static const String _kAdminName = "admin_name";
  static const String _kAdminSocietyId = "admin_society_id";
  static const String _kAdminRole = "admin_role";
  static const String _kAdminSystemRole =
      "admin_system_role"; // ✅ NEW (backward compatible)

  // =========================
  // Role Hint (Admin / Resident / Guard)
  // =========================

  static String? lastRoleHint;

  /// Save last selected role (UI intent only)
  static Future<void> saveLastRoleHint(String role) async {
    lastRoleHint = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoleHint', role);
  }

  static Future<void> setAdminJoinSocietyId(String societyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminJoinSocietyId', societyId);
  }

  static Future<String?> getAdminJoinSocietyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('adminJoinSocietyId');
  }

  static Future<void> clearAdminJoinSocietyId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('adminJoinSocietyId');
  }

  // ✅ Backward compatible aliases (so code can call save/get/clear consistently)
  static Future<void> saveAdminJoinSocietyId(String societyId) async {
    await setAdminJoinSocietyId(societyId);
  }

  /// Load role hint on app startup
  static Future<void> loadLastRoleHint() async {
    final prefs = await SharedPreferences.getInstance();
    lastRoleHint = prefs.getString('lastRoleHint');
  }

  // Resident join-request helper (directory-based onboarding)
  static const String _kResidentJoinSocietyId = "resident_join_society_id";

  static Future<SharedPreferences> _prefs() async {
    return SharedPreferences.getInstance();
  }

  // -----------------------------
  // Guard session
  // -----------------------------
  static Future<void> saveGuardSession({
    required String guardId,
    required String guardName,
    required String societyId,
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_kGuardId, guardId);
    await prefs.setString(_kGuardName, guardName);
    await prefs.setString(_kGuardSocietyId, societyId);
  }

  static Future<void> clearGuardSession() async {
    final prefs = await _prefs();
    await prefs.remove(_kGuardId);
    await prefs.remove(_kGuardName);
    await prefs.remove(_kGuardSocietyId);
  }

  static Future<GuardSession?> getGuardSession() async {
    final prefs = await _prefs();
    final guardId = prefs.getString(_kGuardId);
    final guardName = prefs.getString(_kGuardName);
    final societyId = prefs.getString(_kGuardSocietyId);

    if (guardId == null || guardId.isEmpty) return null;
    return GuardSession(
      guardId: guardId,
      guardName: guardName ?? "",
      societyId: societyId ?? "",
    );
  }

  // -----------------------------
  // Resident session
  // -----------------------------
  static Future<void> saveResidentSession({
    required String residentId,
    required String residentName,
    required String societyId,
    required String flatNo,
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_kResidentId, residentId);
    await prefs.setString(_kResidentName, residentName);
    await prefs.setString(_kResidentSocietyId, societyId);
    await prefs.setString(_kResidentFlatNo, flatNo);
  }

  static Future<void> clearResidentSession() async {
    final prefs = await _prefs();
    await prefs.remove(_kResidentId);
    await prefs.remove(_kResidentName);
    await prefs.remove(_kResidentSocietyId);
    await prefs.remove(_kResidentFlatNo);
  }

  static Future<ResidentSession?> getResidentSession() async {
    final prefs = await _prefs();
    final residentId = prefs.getString(_kResidentId);
    final residentName = prefs.getString(_kResidentName);
    final societyId = prefs.getString(_kResidentSocietyId);
    final flatNo = prefs.getString(_kResidentFlatNo);

    if (residentId == null || residentId.isEmpty) return null;
    return ResidentSession(
      residentId: residentId,
      residentName: residentName ?? "",
      societyId: societyId ?? "",
      flatNo: flatNo ?? "",
    );
  }

  // -----------------------------
  // Convenience
  // -----------------------------
  static Future<bool> hasGuardSession() async {
    final prefs = await _prefs();
    return (prefs.getString(_kGuardId) ?? "").isNotEmpty;
  }

  static Future<bool> hasResidentSession() async {
    final prefs = await _prefs();
    return (prefs.getString(_kResidentId) ?? "").isNotEmpty;
  }

  /// Remember which society the resident requested to join (for pending screen).
  static Future<void> saveResidentJoinSocietyId(String societyId) async {
    final prefs = await _prefs();
    await prefs.setString(_kResidentJoinSocietyId, societyId);
  }

  static Future<String?> getResidentJoinSocietyId() async {
    final prefs = await _prefs();
    final v = prefs.getString(_kResidentJoinSocietyId);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static Future<void> clearResidentJoinSocietyId() async {
    final prefs = await _prefs();
    await prefs.remove(_kResidentJoinSocietyId);
  }

  // -----------------------------
  // Admin session (legacy prefs-based)
  // -----------------------------
  static Future<void> saveAdminSession({
    required String adminId,
    required String adminName,
    required String societyId,
    required String role,
    String systemRole = 'admin', // ✅ NEW default for compatibility
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_kAdminId, adminId);
    await prefs.setString(_kAdminName, adminName);
    await prefs.setString(_kAdminSocietyId, societyId);
    await prefs.setString(_kAdminRole, role);
    await prefs.setString(_kAdminSystemRole, _normalizeSystemRole(systemRole));
  }

  static Future<void> clearAdminSession() async {
    final prefs = await _prefs();
    await prefs.remove(_kAdminId);
    await prefs.remove(_kAdminName);
    await prefs.remove(_kAdminSocietyId);
    await prefs.remove(_kAdminRole);
    await prefs.remove(_kAdminSystemRole); // ✅ NEW
  }

  static Future<AdminSession?> getAdminSession() async {
    final prefs = await _prefs();
    final adminId = prefs.getString(_kAdminId);
    final adminName = prefs.getString(_kAdminName);
    final societyId = prefs.getString(_kAdminSocietyId);
    final role = prefs.getString(_kAdminRole);

    // ✅ read systemRole from legacy admin session, else fallback to firebase session, else default
    final rawSystemRole = prefs.getString(_kAdminSystemRole);

    String systemRole = _normalizeSystemRole(rawSystemRole ?? '');
    if (systemRole.isEmpty) {
      // fallback to firebase session if present
      final fbSystemRole = await _secure.read(key: _kSystemRole);
      systemRole = _normalizeSystemRole(fbSystemRole ?? 'admin');
      if (systemRole.isEmpty) systemRole = 'admin';
    }

    if (adminId == null || adminId.isEmpty) return null;
    return AdminSession(
      adminId: adminId,
      adminName: adminName ?? "",
      societyId: societyId ?? "",
      role: role ?? "ADMIN",
      systemRole: systemRole,
    );
  }

  static Future<bool> hasAdminSession() async {
    final prefs = await _prefs();
    return (prefs.getString(_kAdminId) ?? "").isNotEmpty;
  }

  static Future<void> clearAllSessions() async {
    await clearGuardSession();
    await clearResidentSession();
    await clearAdminSession();
  }

  // -----------------------------
  // Firebase Session (NEW) - unified
  // -----------------------------
  static const String _kUid = "firebase_uid";
  static const String _kSocietyId = "firebase_society_id";
  static const String _kSystemRole = "firebase_system_role";
  static const String _kSocietyRole = "firebase_society_role";
  static const String _kName = "firebase_name";
  static const String _kFlatNo = "firebase_flat_no";

  /// Save Firebase session (unified for all roles)
  static Future<void> saveFirebaseSession({
    required String uid,
    required String societyId,
    required String
        systemRole, // "admin" | "super_admin" | "guard" | "resident"
    String? societyRole,
    required String name,
    String? flatNo,
  }) async {
    await _secure.write(key: _kUid, value: uid);
    await _secure.write(key: _kSocietyId, value: societyId);
    await _secure.write(
        key: _kSystemRole, value: _normalizeSystemRole(systemRole));
    if (societyRole != null) {
      await _secure.write(key: _kSocietyRole, value: societyRole);
    } else {
      // keep storage clean
      await _secure.delete(key: _kSocietyRole);
    }
    await _secure.write(key: _kName, value: name);
    if (flatNo != null) {
      await _secure.write(key: _kFlatNo, value: flatNo);
    } else {
      await _secure.delete(key: _kFlatNo);
    }
  }

  /// Get Firebase session
  static Future<Map<String, dynamic>?> getFirebaseSession() async {
    final uid = await _secure.read(key: _kUid);
    if (uid == null || uid.isEmpty) return null;

    return {
      'uid': uid,
      'societyId': await _secure.read(key: _kSocietyId) ?? '',
      'systemRole': await _secure.read(key: _kSystemRole) ?? '',
      'societyRole': await _secure.read(key: _kSocietyRole),
      'name': await _secure.read(key: _kName) ?? '',
      'flatNo': await _secure.read(key: _kFlatNo),
    };
  }

  /// Clear Firebase session
  static Future<void> clearFirebaseSession() async {
    await _secure.delete(key: _kUid);
    await _secure.delete(key: _kSocietyId);
    await _secure.delete(key: _kSystemRole);
    await _secure.delete(key: _kSocietyRole);
    await _secure.delete(key: _kName);
    await _secure.delete(key: _kFlatNo);
  }

  /// Check if Firebase session exists
  static Future<bool> hasFirebaseSession() async {
    final uid = await _secure.read(key: _kUid);
    return (uid ?? "").isNotEmpty;
  }

  // -----------------------------
  // Helpers
  // -----------------------------
  static String _normalizeSystemRole(String input) {
    final r = input.trim().toLowerCase();
    if (r.isEmpty) return '';

    // normalize super admin variants
    if (r == 'super_admin' || r == 'super admin' || r == 'superadmin') {
      return 'super_admin';
    }

    // keep admin/guard/resident as-is
    if (r == 'admin' || r == 'guard' || r == 'resident') return r;

    // unknown -> return original normalized (or empty if you want strict)
    return r;
  }
}
