import 'package:firebase_auth/firebase_auth.dart';
import '../core/app_logger.dart';

/// FirebaseAuthService - Wrapper for Firebase Authentication
/// 
/// Handles email/password authentication with deterministic email aliases
/// for guards and residents to preserve PIN-based UX
class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Get current user UID
  String? get currentUid => _auth.currentUser?.uid;

  /// Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;

  /// Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      AppLogger.i('User signed out');
    } catch (e, stackTrace) {
      AppLogger.e('Error signing out', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create admin account with email/password
  Future<UserCredential> createAdminAccount({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.i('Creating admin account', data: {'email': email});
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      AppLogger.i('Admin account created', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating admin account', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Sign in admin with email/password
  Future<UserCredential> signInAdmin({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.i('Signing in admin', data: {'email': email});
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      AppLogger.i('Admin signed in', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error signing in admin', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Send password reset email for admin (email/password accounts).
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      AppLogger.i('Sending password reset email', data: {'email': email});
      await _auth.sendPasswordResetEmail(email: email);
      AppLogger.i('Password reset email sent', data: {'email': email});
    } catch (e, stackTrace) {
      AppLogger.e('Error sending password reset email', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Generate deterministic email for guard
  static String getGuardEmail({
    required String societyId,
    required String guardId,
  }) {
    return 'guard_${societyId}_$guardId@gateflow.local';
  }

  /// Derive auth email for guard from a username (phone or email)
  /// - If username contains '@' => treat as normal email (lowercased)
  /// - Else => treat as phone and map to synthetic email
  static String getGuardEmailFromUsername(String username) {
    final raw = username.trim();
    if (raw.contains('@')) {
      return raw.toLowerCase();
    }
    final normalizedPhone = raw.replaceAll(RegExp(r'[^\d]'), '');
    return 'guard_phone_$normalizedPhone@gateflow.local';
  }

  /// Generate deterministic email for resident
  static String getResidentEmail({
    required String societyId,
    required String flatNo,
    required String phone,
  }) {
    // Normalize phone (remove spaces, +, etc.)
    final normalizedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    return 'resident_${societyId}_${flatNo}_$normalizedPhone@gateflow.local';
  }

  /// Create guard account (using deterministic email)
  Future<UserCredential> createGuardAccount({
    required String societyId,
    required String guardId,
    required String pin,
  }) async {
    try {
      final email = getGuardEmail(societyId: societyId, guardId: guardId);
      AppLogger.i('Creating guard account', data: {'email': email, 'societyId': societyId, 'guardId': guardId});
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: pin, // PIN is used as password (temporary MVP approach)
      );
      AppLogger.i('Guard account created', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating guard account', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create guard account using a username (phone or email) + PIN
  Future<UserCredential> createGuardAccountWithUsername({
    required String username,
    required String pin,
  }) async {
    try {
      final email = getGuardEmailFromUsername(username);
      AppLogger.i('Creating guard account (username)', data: {'email': email});
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: pin,
      );
      AppLogger.i('Guard account created (username)', data: {'uid': credential.user?.uid});
      return credential;
    } on FirebaseAuthException catch (e, st) {
      AppLogger.e('Error creating guard account (username)', error: e, stackTrace: st);
      rethrow;
    } catch (e, st) {
      AppLogger.e('Unknown error creating guard account (username)', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Sign in guard (using deterministic email)
  Future<UserCredential> signInGuard({
    required String societyId,
    required String guardId,
    required String pin,
  }) async {
    try {
      final email = getGuardEmail(societyId: societyId, guardId: guardId);
      AppLogger.i('Signing in guard', data: {'email': email, 'societyId': societyId, 'guardId': guardId});
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: pin,
      );
      AppLogger.i('Guard signed in', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error signing in guard', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Sign in guard using username (phone or email) + PIN
  Future<UserCredential> signInGuardWithUsername({
    required String username,
    required String pin,
  }) async {
    try {
      final email = getGuardEmailFromUsername(username);
      AppLogger.i('Signing in guard (username)', data: {'email': email});
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: pin,
      );
      AppLogger.i('Guard signed in (username)', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error signing in guard (username)', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create resident account (using deterministic email)
  Future<UserCredential> createResidentAccount({
    required String societyId,
    required String flatNo,
    required String phone,
    required String pin,
  }) async {
    try {
      final email = getResidentEmail(societyId: societyId, flatNo: flatNo, phone: phone);
      AppLogger.i('Creating resident account', data: {'email': email, 'societyId': societyId, 'flatNo': flatNo});
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: pin, // PIN is used as password (temporary MVP approach)
      );
      AppLogger.i('Resident account created', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error creating resident account', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Sign in resident (using deterministic email - legacy method)
  Future<UserCredential> signInResident({
    required String societyId,
    required String flatNo,
    required String phone,
    required String pin,
  }) async {
    try {
      final email = getResidentEmail(societyId: societyId, flatNo: flatNo, phone: phone);
      AppLogger.i('Signing in resident', data: {'email': email, 'societyId': societyId, 'flatNo': flatNo});
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: pin,
      );
      AppLogger.i('Resident signed in', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error signing in resident', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Sign in resident with email and password (new method)
  Future<UserCredential> signInResidentWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.i('Signing in resident', data: {'email': email});
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      AppLogger.i('Resident signed in', data: {'uid': credential.user?.uid});
      return credential;
    } catch (e, stackTrace) {
      AppLogger.e('Error signing in resident', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<UserCredential> signUpOrSignIn({
  required String email,
  required String password,
}) async {
  try {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
    rethrow;
  }
}



}
