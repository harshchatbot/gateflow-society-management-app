import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_logger.dart';

/// Result of phone verification code sent (no OTP stored; used only to complete sign-in).
class PhoneVerificationResult {
  final String verificationId;
  final int? resendToken;

  const PhoneVerificationResult({required this.verificationId, this.resendToken});
}

/// FirebaseAuthService - Wrapper for Firebase Authentication
///
/// Handles:
/// - Phone OTP as PRIMARY login (mobile-first).
/// - Email/password as OPTIONAL login; deterministic email aliases for guards/residents.
class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Normalize phone to E.164 (India +91). Digits only; if 10 digits prepend +91.
  /// Do not log this value in plaintext.
  static String normalizePhoneForIndia(String input) {
    final digits = input.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    return digits.isEmpty ? input : '+$digits';
  }

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

  // ========== PHONE OTP (PRIMARY LOGIN) ==========
  // Firebase built-in only; no OTPs stored. Session persistence respected by Firebase.

  /// Sends OTP to [phoneNumber]. Use [normalizePhoneForIndia] for India.
  /// Returns [PhoneVerificationResult] when code is sent; complete sign-in with [signInWithPhoneCredential].
  Future<PhoneVerificationResult> verifyPhoneNumber({
    required String phoneNumber,
    int? resendToken,
  }) async {
    final completer = Completer<PhoneVerificationResult>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('verificationCompleted called; use signInWithCredential(credential)'),
          );
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (String verificationId, [int? newResendToken]) {
        if (!completer.isCompleted) {
          completer.complete(PhoneVerificationResult(
            verificationId: verificationId,
            resendToken: newResendToken,
          ));
        }
      },
      codeAutoRetrievalTimeout: (String _) {},
      timeout: const Duration(seconds: 120),
      forceResendingToken: resendToken,
    );
    return completer.future;
  }

  /// Sign in with phone OTP. Call after [verifyPhoneNumber] code is sent.
  Future<UserCredential> signInWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final cred = await _auth.signInWithCredential(credential);
    AppLogger.i('Phone sign-in success', data: {'uid': cred.user?.uid});
    return cred;
  }

  /// Link phone credential to current user (e.g. existing email user adding phone).
  /// Requires currentUser != null.
  Future<UserCredential> linkWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No current user to link phone');
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final cred = await user.linkWithCredential(credential);
    AppLogger.i('Phone linked to user', data: {'uid': cred.user?.uid});
    return cred;
  }

  /// Link email/password to current user (optional email in profile).
  Future<UserCredential> linkWithEmailCredential({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No current user to link email');
    final credential = EmailAuthProvider.credential(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final cred = await user.linkWithCredential(credential);
    AppLogger.i('Email linked to user', data: {'uid': cred.user?.uid});
    return cred;
  }

  /// Create admin account with email/password
  Future<UserCredential> createAdminAccount({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.i('Creating admin account');
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
      AppLogger.i('Signing in admin');
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
      AppLogger.i('Sending password reset email');
      await _auth.sendPasswordResetEmail(email: email);
      AppLogger.i('Password reset email sent');
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
      AppLogger.i('Creating guard account', data: {'societyId': societyId, 'guardId': guardId});
      final password = _derivePasswordFromPin(
        context: 'guard:$societyId:$guardId',
        pin: pin,
      );
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
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
      AppLogger.i('Creating guard account (username)');
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
      AppLogger.i('Signing in guard', data: {'societyId': societyId, 'guardId': guardId});
      final password = _derivePasswordFromPin(
        context: 'guard:$societyId:$guardId',
        pin: pin,
      );
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        AppLogger.i('Guard signed in', data: {'uid': credential.user?.uid});
        return credential;
      } on FirebaseAuthException catch (e) {
        // Backward compatibility: try plain PIN, then migrate password
        if (e.code == 'wrong-password') {
          AppLogger.w('Guard hashed password sign-in failed, trying legacy PIN', error: e);
          final legacyCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: pin,
          );
          AppLogger.i('Guard signed in with legacy PIN, migrating to hashed password', data: {
            'uid': legacyCredential.user?.uid,
          });
          try {
            await legacyCredential.user?.updatePassword(password);
          } catch (updateError, st) {
            AppLogger.e('Failed to migrate guard password to hashed', error: updateError, stackTrace: st);
          }
          return legacyCredential;
        }
        rethrow;
      }
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
      AppLogger.i('Signing in guard (username)');
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
      AppLogger.i('Creating resident account', data: {'societyId': societyId, 'flatNo': flatNo});
      final password = _derivePasswordFromPin(
        context: 'resident:$societyId:$flatNo:$phone',
        pin: pin,
      );
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
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
      AppLogger.i('Signing in resident', data: {'societyId': societyId, 'flatNo': flatNo});
      final password = _derivePasswordFromPin(
        context: 'resident:$societyId:$flatNo:$phone',
        pin: pin,
      );
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        AppLogger.i('Resident signed in', data: {'uid': credential.user?.uid});
        return credential;
      } on FirebaseAuthException catch (e) {
        // Backward compatibility: try plain PIN, then migrate password
        if (e.code == 'wrong-password') {
          AppLogger.w('Resident hashed password sign-in failed, trying legacy PIN', error: e);
          final legacyCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: pin,
          );
          AppLogger.i('Resident signed in with legacy PIN, migrating to hashed password', data: {
            'uid': legacyCredential.user?.uid,
          });
          try {
            await legacyCredential.user?.updatePassword(password);
          } catch (updateError, st) {
            AppLogger.e('Failed to migrate resident password to hashed', error: updateError, stackTrace: st);
          }
          return legacyCredential;
        }
        rethrow;
      }
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
      AppLogger.i('Signing in resident (email/password)');
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

  /// Derive a strong password string from a short PIN + context.
  /// This avoids storing the raw PIN as the Firebase password.
  static String _derivePasswordFromPin({
    required String context,
    required String pin,
  }) {
    final normalizedPin = pin.trim();
    final input = '$context|$normalizedPin|sentinel-v1';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes).toString(); // 64-char hex
    // Optionally add a prefix to avoid pure-hex-only passwords if needed.
    return 'Sf_${digest}_p';
  }
}
