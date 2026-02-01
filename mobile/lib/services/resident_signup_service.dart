import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../core/app_error.dart';
import '../core/app_logger.dart';
import 'firestore_service.dart';

class Result<T> {
  final T? data;
  final AppError? error;
  /// Success when no error; data may be null for void operations (e.g. rejectSignup)
  bool get isSuccess => error == null;

  Result.success(this.data) : error = null;
  Result.failure(this.error) : data = null;
}

class ResidentSignupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _uuid = const Uuid();

  /// Get reference to resident signups collection
  CollectionReference _residentSignupsRef(String societyId) {
    return _firestore
        .collection('societies')
        .doc(societyId)
        .collection('residentSignups');
  }

  /// Create a resident signup request (NO READ QUERIES)
  /// - Works even when user is not authenticated
  Future<Result<String>> createSignupRequest({
    required String societyCode,
    required String name,
    required String email,
    required String phone,
    required String flatNo,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final normalizedPhone = phone.trim();
      final normalizedFlatNo = flatNo.trim().toUpperCase();

      // Normalize code
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

      if (normalizedEmail.isEmpty || !normalizedEmail.contains("@")) {
        return Result.failure(AppError(
          userMessage: "Please enter a valid email.",
          technicalMessage: "Invalid email: $email",
        ));
      }

      if (normalizedFlatNo.isEmpty) {
        return Result.failure(AppError(
          userMessage: "Please enter a valid flat number.",
          technicalMessage: "Invalid flatNo: $flatNo",
        ));
      }

      // 1) Resolve societyId from societyCodes/{CODE}
      final codeSnap = await _firestore
          .collection('societyCodes')
          .doc(normalizedCode)
          .get();

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
          userMessage: "Society is inactive or invalid. Please contact support.",
          technicalMessage: "societyId missing or inactive for code=$normalizedCode",
        ));
      }

      AppLogger.i("Creating resident signup", data: {
        "societyId": societyId,
        "societyCode": normalizedCode,
        "email": normalizedEmail,
        "flatNo": normalizedFlatNo,
      });

      // 2) Create Firebase Auth user FIRST (needed for authenticated queries)
      UserCredential userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
        );
      } catch (e) {
        if (e.toString().contains('email-already-in-use')) {
          return Result.failure(AppError(
            userMessage: "An account with this email already exists. Please login instead.",
            technicalMessage: "Email already in use: $normalizedEmail",
          ));
        }
        return Result.failure(AppError(
          userMessage: "Failed to create account. Please try again.",
          technicalMessage: e.toString(),
        ));
      }

      final uid = userCredential.user?.uid;
      if (uid == null) {
        return Result.failure(AppError(
          userMessage: "Failed to create account",
          technicalMessage: "UID is null after auth creation",
        ));
      }

      // 3) Check for duplicate phone number (ACTIVE residents only)
      // Must be done AFTER auth so user is authenticated for Firestore query
      if (normalizedPhone.isNotEmpty) {
        AppLogger.i("Checking for duplicate phone number");
        try {
          final firestoreService = FirestoreService();
          final duplicateUid = await firestoreService.checkDuplicatePhone(
            societyId: societyId,
            phone: normalizedPhone,
          );
          if (duplicateUid != null) {
            AppLogger.w("Duplicate phone number found", data: {
              "phone": normalizedPhone,
              "existingUid": duplicateUid,
            });
            // Delete the just-created auth account since phone is duplicate
            try {
              await userCredential.user?.delete();
              AppLogger.i("Deleted auth account due to duplicate phone");
            } catch (deleteError) {
              AppLogger.e("Failed to delete auth account after duplicate phone", error: deleteError);
            }
            return Result.failure(AppError(
              userMessage: "This phone number is already registered in this society. Please use a different phone number or contact admin.",
              technicalMessage: "DUPLICATE_PHONE: $normalizedPhone already exists for uid=$duplicateUid",
            ));
          }
        } catch (e, st) {
          AppLogger.e("Error checking duplicate phone, proceeding anyway", error: e, stackTrace: st);
          // Don't block signup if duplicate check fails - better to allow than block
        }
      }

      // 5) Create society member doc (active=false)
      final societyMemberRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid);

      final memberData = {
        'uid': uid,
        'societyId': societyId,
        'systemRole': 'resident', // lowercase
        'active': false,          // pending
        'name': name.trim(),
        'email': normalizedEmail,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'flatNo': normalizedFlatNo,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 6) Root pointer (keep in sync)
      final rootPointerRef = _firestore.collection('members').doc(uid);
      final pointerData = {
        'uid': uid,
        'societyId': societyId,
        'systemRole': 'resident',
        'active': false,
        'name': name.trim(),
        'email': normalizedEmail,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'flatNo': normalizedFlatNo,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final batch = _firestore.batch();
      batch.set(societyMemberRef, memberData, SetOptions(merge: true));
      batch.set(rootPointerRef, pointerData, SetOptions(merge: true));
      await batch.commit();

      AppLogger.i("Resident signup created successfully", data: {
        "uid": uid,
        "societyId": societyId,
        "email": normalizedEmail,
        "flatNo": normalizedFlatNo,
      });

      return Result.success(uid);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("Resident createSignupRequest FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, st) {
      AppLogger.e("Resident createSignupRequest unknown error", error: e, stackTrace: st);
      return Result.failure(AppError(
        userMessage: "Failed to create signup request",
        technicalMessage: e.toString(),
      ));
    }
  }



  /// Get pending signup requests (for admin)
  /// Queries members with active=false and systemRole=resident
  Future<Result<List<Map<String, dynamic>>>> getPendingSignups({
    required String societyId,
  }) async {
    try {
      // Query members with active=false and systemRole=resident (new flow)
      final querySnapshot = await _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .where('systemRole', isEqualTo: 'resident')
          .where('active', isEqualTo: false)
          .get();

      final List<Map<String, dynamic>> signups = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // doc.id IS the uid (document is created with uid as the document ID)
        // Always use doc.id as the primary identifier for consistency
        final uid = doc.id;
        
        // Convert Firestore Timestamp to ISO string
        DateTime createdAt;
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else if (data['created_at'] is Timestamp) {
          createdAt = (data['created_at'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }

        signups.add({
          'signup_id': uid, // Use doc.id directly (this is the uid)
          'society_id': data['societyId'] ?? societyId,
          'name': data['name'] ?? '',
          'email': data['email'] ?? '',
          'phone': data['phone'] ?? '',
          'flat_no': data['flatNo'] ?? data['flat_no'] ?? '',
          'status': 'PENDING',
          'created_at': createdAt.toIso8601String(),
          'uid': uid, // Use doc.id directly
        });
      }

      // Sort by createdAt descending (in memory since we removed orderBy to avoid index)
      signups.sort((a, b) {
        final aTime = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
        final bTime = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
        return bTime.compareTo(aTime);
      });

      AppLogger.i("Found ${signups.length} pending resident signups (from members)");
      return Result.success(signups);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("getPendingSignups FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to load signup requests",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getPendingSignups unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Approve a signup request (for admin)
  /// New flow: Resident already has Firebase Auth account and member doc with active=false
  /// Just need to set active=true
  Future<Result<Map<String, dynamic>>> approveSignup({
    required String societyId,
    required String signupId, // This is now the uid
    required String adminUid,
  }) async {
    try {
      // signupId is now the uid (from the new flow)
      final uid = signupId;
      
      final memberRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid);

      final memberDoc = await memberRef.get();

      if (!memberDoc.exists) {
        return Result.failure(AppError(
          userMessage: "Resident not found",
          technicalMessage: "Member $uid not found in society $societyId",
        ));
      }

      final memberData = memberDoc.data() as Map<String, dynamic>;
      
      if (memberData['active'] == true) {
        return Result.failure(AppError(
          userMessage: "Resident is already approved",
          technicalMessage: "Member $uid is already active",
        ));
      }

      if (memberData['systemRole'] != 'resident') {
        return Result.failure(AppError(
          userMessage: "User is not a resident",
          technicalMessage: "Member $uid has systemRole: ${memberData['systemRole']}",
        ));
      }

      AppLogger.i("Approving resident signup", data: {
        "uid": uid,
        "societyId": societyId,
        "email": memberData['email'],
      });

      // Update member document to active=true
      await memberRef.update({
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update root pointer (optional - wrap in try-catch since rules may restrict)
      try {
        await _firestore.collection('members').doc(uid).update({
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Root pointer update failed (permission issue) - not critical since society member doc is source of truth
        AppLogger.w("Root pointer update failed (non-critical)", data: {
          "uid": uid,
          "error": e.toString(),
        });
      }

      AppLogger.i("Resident signup approved successfully", data: {
        "uid": uid,
        "societyId": societyId,
      });

      return Result.success({
        'signup_id': uid,
        'uid': uid,
        'email': memberData['email'] ?? '',
        'status': 'APPROVED',
      });
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("approveSignup FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to approve signup request",
        technicalMessage: e.toString(),
      );
      AppLogger.e("approveSignup unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Reject a signup request (for admin)
  /// New flow: Delete member document and root pointer
  /// Also handles legacy residentSignups collection
  Future<Result<void>> rejectSignup({
    required String societyId,
    required String signupId, // This is the uid (document ID)
    required String adminUid,
    String? reason,
  }) async {
    try {
      // signupId is the uid (document ID in the members collection)
      final uid = signupId.trim();
      
      if (uid.isEmpty) {
        AppLogger.e("rejectSignup called with empty signupId");
        return Result.failure(AppError(
          userMessage: "Invalid signup request",
          technicalMessage: "signupId is empty",
        ));
      }

      AppLogger.i("Rejecting signup", data: {
        "uid": uid,
        "societyId": societyId,
        "adminUid": adminUid,
      });
      
      bool documentDeleted = false;
      
      // Try to delete from members collection (new flow)
      final memberRef = _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid);

      final memberDoc = await memberRef.get();

      if (memberDoc.exists) {
        await memberRef.delete();
        documentDeleted = true;
        AppLogger.i("Deleted member document", data: {"path": memberRef.path});
      } else {
        AppLogger.w("Member document not found, checking legacy collection", data: {
          "uid": uid,
          "path": memberRef.path,
        });
      }

      // Also try to delete from legacy residentSignups collection
      try {
        final legacyRef = _firestore
            .collection('societies')
            .doc(societyId)
            .collection('residentSignups')
            .doc(uid);
        
        final legacyDoc = await legacyRef.get();
        if (legacyDoc.exists) {
          await legacyRef.delete();
          documentDeleted = true;
          AppLogger.i("Deleted legacy signup document", data: {"path": legacyRef.path});
        }
      } catch (e) {
        AppLogger.w("Error checking/deleting legacy signup", data: {"error": e.toString()});
      }

      if (!documentDeleted) {
        // Document not found in either collection - might have been already deleted
        AppLogger.w("No document found to delete - may have been already rejected");
        // Return success anyway since the goal (removing the signup) is achieved
        return Result.success(null);
      }

      // Delete root pointer (optional - wrap in try-catch since rules may restrict)
      try {
        await _firestore.collection('members').doc(uid).delete();
      } catch (e) {
        // Root pointer delete failed (permission issue) - not critical since society member doc is source of truth
        AppLogger.w("Root pointer delete failed (non-critical)", data: {
          "uid": uid,
          "error": e.toString(),
        });
      }

      AppLogger.i("Resident signup rejected", data: {
        "uid": uid,
        "reason": reason,
      });

      return Result.success(null);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("rejectSignup FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to reject signup request",
        technicalMessage: e.toString(),
      );
      AppLogger.e("rejectSignup unknown error", error: err.technicalMessage, stackTrace: stackTrace);
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
      case 'already-exists':
        userMessage = "A signup request with this information already exists.";
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
