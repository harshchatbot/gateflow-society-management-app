import 'package:shared_preferences/shared_preferences.dart';

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
  final String role;

  AdminSession({
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.role,
  });
}

class Storage {
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

  // -----------------------------
  // Admin session
  // -----------------------------
  static Future<void> saveAdminSession({
    required String adminId,
    required String adminName,
    required String societyId,
    required String role,
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_kAdminId, adminId);
    await prefs.setString(_kAdminName, adminName);
    await prefs.setString(_kAdminSocietyId, societyId);
    await prefs.setString(_kAdminRole, role);
  }

  static Future<void> clearAdminSession() async {
    final prefs = await _prefs();
    await prefs.remove(_kAdminId);
    await prefs.remove(_kAdminName);
    await prefs.remove(_kAdminSocietyId);
    await prefs.remove(_kAdminRole);
  }

  static Future<AdminSession?> getAdminSession() async {
    final prefs = await _prefs();
    final adminId = prefs.getString(_kAdminId);
    final adminName = prefs.getString(_kAdminName);
    final societyId = prefs.getString(_kAdminSocietyId);
    final role = prefs.getString(_kAdminRole);

    if (adminId == null || adminId.isEmpty) return null;
    return AdminSession(
      adminId: adminId,
      adminName: adminName ?? "",
      societyId: societyId ?? "",
      role: role ?? "ADMIN",
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
}
