import 'package:shared_preferences/shared_preferences.dart';

/// Local storage for "first-time tour" flags per role.
/// Used to auto-run the in-app guided tour only on first successful login per role.
class TourStorage {
  TourStorage._();

  static const String _keyGuard = 'hasSeenTour_guard';
  static const String _keyResident = 'hasSeenTour_resident';
  static const String _keyAdmin = 'hasSeenTour_admin';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<bool> hasSeenTourGuard() async {
    final prefs = await _prefs();
    return prefs.getBool(_keyGuard) ?? false;
  }

  static Future<bool> hasSeenTourResident() async {
    final prefs = await _prefs();
    return prefs.getBool(_keyResident) ?? false;
  }

  static Future<bool> hasSeenTourAdmin() async {
    final prefs = await _prefs();
    return prefs.getBool(_keyAdmin) ?? false;
  }

  static Future<bool> hasSeenTourForRole(String role) async {
    switch (role.toLowerCase()) {
      case 'guard':
        return hasSeenTourGuard();
      case 'resident':
        return hasSeenTourResident();
      case 'admin':
      case 'super_admin':
        return hasSeenTourAdmin();
      default:
        return true;
    }
  }

  static Future<void> setHasSeenTourGuard() async {
    final prefs = await _prefs();
    await prefs.setBool(_keyGuard, true);
  }

  static Future<void> setHasSeenTourResident() async {
    final prefs = await _prefs();
    await prefs.setBool(_keyResident, true);
  }

  static Future<void> setHasSeenTourAdmin() async {
    final prefs = await _prefs();
    await prefs.setBool(_keyAdmin, true);
  }

  static Future<void> setHasSeenTourForRole(String role) async {
    switch (role.toLowerCase()) {
      case 'guard':
        await setHasSeenTourGuard();
        break;
      case 'resident':
        await setHasSeenTourResident();
        break;
      case 'admin':
      case 'super_admin':
        await setHasSeenTourAdmin();
        break;
    }
  }
}
