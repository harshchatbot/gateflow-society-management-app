import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../core/app_error.dart';
import '../core/app_logger.dart';
import 'firestore_service.dart';

class Result<T> {
  final T? data;
  final AppError? error;
  bool get isSuccess => data != null && error == null;

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

      // 2) Create Firebase Auth user
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

      // 3) Create society member doc (active=false)
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

      // 4) Root pointer (keep in sync)
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
  Future<Result<List<Map<String, dynamic>>>> getPendingSignups({
    required String societyId,
  }) async {
    try {
      final querySnapshot = await _residentSignupsRef(societyId)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('created_at', descending: true)
          .get();

      final List<Map<String, dynamic>> signups = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Convert Firestore Timestamp to ISO string
        DateTime createdAt;
        if (data['created_at'] is Timestamp) {
          createdAt = (data['created_at'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }

        signups.add({
          'signup_id': data['signup_id'] ?? doc.id,
          'society_id': data['society_id'] ?? societyId,
          'name': data['name'] ?? '',
          'email': data['email'] ?? '',
          'phone': data['phone'] ?? '',
          'flat_no': data['flat_no'] ?? '',
          'status': data['status'] ?? 'PENDING',
          'created_at': createdAt.toIso8601String(),
          'password': data['password'], // Include password for account creation
        });
      }

      AppLogger.i("Found ${signups.length} pending signups");
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
  /// This will:
  /// 1. Create Firebase Auth account
  /// 2. Create member record
  /// 3. Update signup status to APPROVED
  Future<Result<Map<String, dynamic>>> approveSignup({
    required String societyId,
    required String signupId,
    required String adminUid,
  }) async {
    try {
      final signupRef = _residentSignupsRef(societyId).doc(signupId);
      final signupDoc = await signupRef.get();

      if (!signupDoc.exists) {
        return Result.failure(AppError(
          userMessage: "Signup request not found",
          technicalMessage: "Signup $signupId not found in society $societyId",
        ));
      }

      final signupData = signupDoc.data() as Map<String, dynamic>;
      
      if (signupData['status'] != 'PENDING') {
        return Result.failure(AppError(
          userMessage: "Signup request is not pending",
          technicalMessage: "Signup $signupId has status: ${signupData['status']}",
        ));
      }

      final email = signupData['email'] as String;
      final password = signupData['password'] as String;
      final name = signupData['name'] as String;
      final phone = signupData['phone'] as String;
      final flatNo = signupData['flat_no'] as String;

      AppLogger.i("Approving resident signup", data: {
        "signupId": signupId,
        "email": email,
        "flatNo": flatNo,
      });

      // 1. Create Firebase Auth account
      UserCredential userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (e) {
        // If user already exists, try to sign in and get the user
        if (e.toString().contains('email-already-in-use')) {
          // User exists, sign in to get the user
          userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final uid = userCredential.user?.uid;
      if (uid == null) {
        throw Exception("Failed to create user account");
      }

      // 2. Create member record using FirestoreService
      final firestoreService = FirestoreService();
      await firestoreService.setMember(
        societyId: societyId,
        uid: uid,
        systemRole: 'resident',
        name: name,
        phone: phone,
        email: email, // Include email
        flatNo: flatNo,
        active: true,
      );

      // 3. Update signup status
      final now = FieldValue.serverTimestamp();
      await signupRef.update({
        'status': 'APPROVED',
        'approved_by': adminUid,
        'approved_at': now,
        'updated_at': now,
        // Remove password from document for security
        'password': FieldValue.delete(),
      });

      AppLogger.i("Resident signup approved successfully", data: {
        "signupId": signupId,
        "uid": uid,
        "email": email,
      });

      return Result.success({
        'signup_id': signupId,
        'uid': uid,
        'email': email,
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
  Future<Result<void>> rejectSignup({
    required String societyId,
    required String signupId,
    required String adminUid,
    String? reason,
  }) async {
    try {
      final signupRef = _residentSignupsRef(societyId).doc(signupId);
      final signupDoc = await signupRef.get();

      if (!signupDoc.exists) {
        return Result.failure(AppError(
          userMessage: "Signup request not found",
          technicalMessage: "Signup $signupId not found in society $societyId",
        ));
      }

      final now = FieldValue.serverTimestamp();
      await signupRef.update({
        'status': 'REJECTED',
        'rejected_by': adminUid,
        'rejected_at': now,
        'rejection_reason': reason,
        'updated_at': now,
        // Remove password from document for security
        'password': FieldValue.delete(),
      });

      AppLogger.i("Resident signup rejected", data: {
        "signupId": signupId,
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
