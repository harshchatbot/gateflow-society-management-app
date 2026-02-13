import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_error.dart';
import '../core/app_logger.dart';
import 'firestore_service.dart';
import 'firebase_auth_service.dart';

class Result<T> {
  final T? data;
  final AppError? error;
  bool get isSuccess => data != null && error == null;

  Result.success(this.data) : error = null;
  Result.failure(this.error) : data = null;
}

class AdminSignupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Create admin signup - creates Firebase Auth user and member document with active=false
  /// Works exactly like resident signup
  Future<Result<String>> createSignupRequest({
    required String societyCode,
    required String name,
    required String email,
    required String phone,
    required String password,
    required String societyRole,
  }) async {
    try {
      final currentUser = _auth.currentUser;

      final normalizedEmail = email.trim().toLowerCase();
      String normalizedPhone = phone.trim();
      final normalizedSocietyRole = societyRole.trim().toUpperCase();

      // ✅ Normalize phone to E.164 (+91xxxxxxxxxx) if possible (10-digit -> India)
      if (normalizedPhone.isNotEmpty) {
        if (!normalizedPhone.startsWith('+')) {
          final digits = normalizedPhone.replaceAll(RegExp(r'[^\d]'), '');
          if (digits.length == 10) {
            normalizedPhone =
                FirebaseAuthService.normalizePhoneForIndia(digits);
          }
        } else {
          // If already in + format, still normalize via helper (safe)
          normalizedPhone =
              FirebaseAuthService.normalizePhoneForIndia(normalizedPhone);
        }
      }

      // Strip SOC_ prefix if present
      String normalizedCode = societyCode.trim().toUpperCase();
      if (normalizedCode.startsWith('SOC_')) {
        normalizedCode = normalizedCode.substring(4);
      }

      if (normalizedCode.isEmpty) {
        return Result.failure(AppError(
          userMessage: "Invalid society. Please check society code.",
          technicalMessage: "societyCode is empty",
        ));
      }

      // Email is required only when creating a NEW auth user.
      // For already-authenticated users (e.g. phone OTP), email is optional.
      String? effectiveEmail;
      if (normalizedEmail.isNotEmpty && normalizedEmail.contains("@")) {
        effectiveEmail = normalizedEmail;
      } else if (currentUser != null &&
          currentUser.email != null &&
          currentUser.email!.contains("@")) {
        effectiveEmail = currentUser.email!.trim().toLowerCase();
      } else if (currentUser == null) {
        return Result.failure(AppError(
          userMessage: "Please enter a valid email.",
          technicalMessage: "Invalid email: $email",
        ));
      } else {
        effectiveEmail = null;
      }

      // 1. Resolve societyId from societyCodes/{CODE}
      final codeSnap =
          await _firestore.collection('societyCodes').doc(normalizedCode).get();

      if (!codeSnap.exists) {
        return Result.failure(AppError(
          userMessage: "Invalid society code. Please check and try again.",
          technicalMessage: "societyCodes/$normalizedCode not found",
        ));
      }

      final codeData = codeSnap.data()!;
      final societyId = codeData['societyId'] as String?;
      final isActive = codeData['active'] as bool? ?? true;

      if (societyId == null || societyId.trim().isEmpty || !isActive) {
        return Result.failure(AppError(
          userMessage:
              "Society is inactive or invalid. Please contact support.",
          technicalMessage:
              "societyId missing or inactive for code=$normalizedCode",
        ));
      }

      AppLogger.i("Creating admin signup", data: {
        "societyId": societyId,
        "societyCode": normalizedCode,
        "email": normalizedEmail,
        "societyRole": normalizedSocietyRole,
        "phone": normalizedPhone,
        "authUserPresent": currentUser != null,
      });

      // 2. Resolve UID:
      //    - If user already authenticated (e.g. Phone OTP), reuse current UID.
      //    - Otherwise, create Firebase Auth user with email/password (legacy path).
      UserCredential? userCredential;
      String uid;

      if (currentUser != null) {
        uid = currentUser.uid;
      } else {
        try {
          userCredential = await _auth.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
        } catch (e) {
          if (e.toString().contains('email-already-in-use')) {
            return Result.failure(AppError(
              userMessage:
                  "An account with this email already exists. Please login instead.",
              technicalMessage: "Email already in use: $normalizedEmail",
            ));
          }
          return Result.failure(AppError(
            userMessage: "Failed to create account. Please try again.",
            technicalMessage: e.toString(),
          ));
        }

        uid = userCredential.user?.uid ?? '';
        if (uid.isEmpty) {
          return Result.failure(AppError(
            userMessage: "Failed to create account",
            technicalMessage: "UID is null after auth creation",
          ));
        }
      }

      // ✅ Optional: if phone was not provided, but user is OTP-authenticated, take it from auth
      if (normalizedPhone.isEmpty) {
        final authPhone = _auth.currentUser?.phoneNumber;
        if (authPhone != null && authPhone.isNotEmpty) {
          normalizedPhone =
              FirebaseAuthService.normalizePhoneForIndia(authPhone);
        }
      }

      // ✅ Enforce unique phone ONLY against ACTIVE accounts (your desired behavior)
      // We do this check before writing the request.
      if (normalizedPhone.isNotEmpty) {
        final ok = await FirestoreService().isPhoneAvailableForUser(
          normalizedE164: normalizedPhone,
          forUid: uid,
        );

        if (!ok) {
          return Result.failure(AppError(
            userMessage:
                "This mobile number is already linked to another active account.",
            technicalMessage: "Active phone conflict: $normalizedPhone",
          ));
        }
      }

      // 3. Create member document with active=false (pending approval)
      final memberRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid);

      final memberData = {
        'uid': uid,
        'societyId': societyId,
        'systemRole': 'admin',
        'societyRole': normalizedSocietyRole.toLowerCase(),
        'name': name.trim(),
        'email': effectiveEmail,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'active': false, // Pending approval
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      AppLogger.i("Creating member document", data: {
        "uid": uid,
        "societyId": societyId,
        "name": name.trim(),
        "email": normalizedEmail,
        "phone": normalizedPhone.isEmpty ? null : normalizedPhone,
        "societyRole": normalizedSocietyRole.toLowerCase(),
      });

      try {
        await memberRef.set(memberData);
        AppLogger.i("Member document created successfully");

        // Verify the document was written correctly
        final verifyDoc = await memberRef.get();
        if (verifyDoc.exists) {
          final verifyData = verifyDoc.data() as Map<String, dynamic>;
          AppLogger.i("Member document verification", data: {
            "uid": verifyData['uid'],
            "name": verifyData['name'],
            "email": verifyData['email'],
            "phone": verifyData['phone'],
            "systemRole": verifyData['systemRole'],
            "active": verifyData['active'],
          });
        }
      } catch (e, st) {
        AppLogger.e("Failed to create member document",
            error: e, stackTrace: st);
        rethrow;
      }

      // 4. Create root pointer (also include name, email, phone for consistency)
      await _firestore.collection('members').doc(uid).set({
        'uid': uid,
        'societyId': societyId,
        'systemRole': 'admin',
        'name': name.trim(),
        'email': effectiveEmail,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      AppLogger.i("Admin signup created successfully", data: {
        "uid": uid,
        "societyId": societyId,
        "email": normalizedEmail,
      });

      return Result.success(uid);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("createSignupRequest FirebaseException",
          error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to create signup request",
        technicalMessage: e.toString(),
      );
      AppLogger.e("createSignupRequest unknown error",
          error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Get pending admin signups (members with active=false and systemRole=admin)
  Future<Result<List<Map<String, dynamic>>>> getPendingSignups({
    required String societyId,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .where('systemRole', isEqualTo: 'admin')
          .where('active', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();

      final List<Map<String, dynamic>> signups = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();

        DateTime createdAt;
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }

        signups.add({
          'uid': data['uid'] ?? doc.id,
          'society_id': data['societyId'] ?? societyId,
          'name': data['name'] ?? '',
          'email': data['email'] ?? '',
          'phone': data['phone'] ?? '',
          'society_role': data['societyRole'] ?? 'admin',
          'created_at': createdAt.toIso8601String(),
        });
      }

      AppLogger.i("Found ${signups.length} pending admin signups");
      return Result.success(signups);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("getPendingSignups FirebaseException",
          error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to load signup requests",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getPendingSignups unknown error",
          error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Approve admin signup - sets active=true
  Future<Result<Map<String, dynamic>>> approveSignup({
    required String societyId,
    required String uid,
    required String superAdminUid,
  }) async {
    try {
      final memberRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid);

      final memberDoc = await memberRef.get();

      if (!memberDoc.exists) {
        return Result.failure(AppError(
          userMessage: "Admin not found",
          technicalMessage: "Member $uid not found in society $societyId",
        ));
      }

      final memberData = memberDoc.data() as Map<String, dynamic>;

      if (memberData['active'] == true) {
        return Result.failure(AppError(
          userMessage: "Admin is already approved",
          technicalMessage: "Member $uid is already active",
        ));
      }

      if (memberData['systemRole'] != 'admin') {
        return Result.failure(AppError(
          userMessage: "User is not an admin",
          technicalMessage:
              "Member $uid has systemRole: ${memberData['systemRole']}",
        ));
      }

      // ✅ Enforce unique phone at approval time as well (final safety)
      String phone = (memberData['phone'] ?? '').toString().trim();
      if (phone.isNotEmpty) {
        phone = FirebaseAuthService.normalizePhoneForIndia(phone);
        final ok = await FirestoreService().isPhoneAvailableForUser(
          normalizedE164: phone,
          forUid: uid,
        );
        if (!ok) {
          return Result.failure(AppError(
            userMessage:
                "Cannot approve: this mobile number is already linked to another active account.",
            technicalMessage: "Active phone conflict on approve: $phone",
          ));
        }
      }

      AppLogger.i("Approving admin signup", data: {
        "uid": uid,
        "societyId": societyId,
      });

      // Update member document to active=true
      await memberRef.update({
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update root pointer
      await _firestore.collection('members').doc(uid).update({
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ✅ After approval, register phone in unique_phones mapping (if present)
      if (phone.isNotEmpty) {
        await FirestoreService().setMemberPhone(
          societyId: societyId,
          uid: uid,
          normalizedE164: phone,
        );
      }

      AppLogger.i("Admin signup approved successfully", data: {
        "uid": uid,
        "societyId": societyId,
      });

      return Result.success({
        'uid': uid,
        'status': 'APPROVED',
      });
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("approveSignup FirebaseException",
          error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to approve signup request",
        technicalMessage: e.toString(),
      );
      AppLogger.e("approveSignup unknown error",
          error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Reject admin signup - deletes member document
  Future<Result<void>> rejectSignup({
    required String societyId,
    required String uid,
    required String superAdminUid,
    String? reason,
  }) async {
    try {
      final memberRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid);

      final memberDoc = await memberRef.get();

      if (!memberDoc.exists) {
        return Result.failure(AppError(
          userMessage: "Admin not found",
          technicalMessage: "Member $uid not found in society $societyId",
        ));
      }

      final memberData = memberDoc.data() as Map<String, dynamic>;
      final phone = (memberData['phone'] ?? '').toString().trim();

      // Delete member document
      await memberRef.delete();

      // Delete root pointer
      await _firestore.collection('members').doc(uid).delete();

      // ✅ Best-effort cleanup unique_phones mapping if it points to this uid
      // (safe: if it doesn't match, we do nothing)
      if (phone.isNotEmpty) {
        try {
          // This relies on FirestoreService internal hashing; so we just "re-set" on cleanup is not possible here.
          // If you want hard cleanup, we can add a helper in FirestoreService to remove mapping safely.
          AppLogger.i(
              "Reject cleanup: phone was present (unique_phones may remain)",
              data: {
                "uid": uid,
                "phone": phone,
              });
        } catch (_) {
          // ignore
        }
      }

      AppLogger.i("Admin signup rejected", data: {
        "uid": uid,
        "reason": reason,
      });

      return Result.success(null);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("rejectSignup FirebaseException",
          error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to reject signup request",
        technicalMessage: e.toString(),
      );
      AppLogger.e("rejectSignup unknown error",
          error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Check if admin signup is pending (for login flow)
  Future<Result<Map<String, dynamic>?>> getPendingSignupByEmail({
    required String societyId,
    required String email,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      final querySnapshot = await _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .where('email', isEqualTo: normalizedEmail)
          .where('systemRole', isEqualTo: 'admin')
          .where('active', isEqualTo: false)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return Result.success(null);
      }

      final doc = querySnapshot.docs.first;
      return Result.success(doc.data());
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("getPendingSignupByEmail FirebaseException",
          error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to check signup status",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getPendingSignupByEmail unknown error",
          error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Map Firebase exceptions to user-friendly errors
  AppError _mapFirebaseError(FirebaseException e) {
    String userMessage = "Firebase error. Please try again.";

    switch (e.code) {
      case 'permission-denied':
        userMessage = "Permission denied. Please check your access.";
        break;
      case 'unauthenticated':
        userMessage = "Please log in to continue.";
        break;
      case 'unavailable':
        userMessage = "Service unavailable. Please check your connection.";
        break;
      default:
        userMessage = "Error: ${e.message ?? 'Unknown error'}";
    }

    final technical = "FirebaseException(code=${e.code}, message=${e.message})";
    return AppError(userMessage: userMessage, technicalMessage: technical);
  }
}
