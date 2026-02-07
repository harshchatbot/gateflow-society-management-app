import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/app_error.dart';
import '../core/app_logger.dart';
import '../core/api_client.dart';
import '../models/visitor.dart';

class Result<T> {
  final T? data;
  final AppError? error;
  bool get isSuccess => data != null && error == null;

  Result.success(this.data) : error = null;
  Result.failure(this.error) : data = null;
}

class FirebaseVisitorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference _visitorsRef(String societyId) {
    return _firestore.collection('societies').doc(societyId).collection('visitors');
  }

  Reference _visitorPhotoRef(String societyId, String visitorId) {
    return _storage.ref().child('societies/$societyId/visitors/$visitorId.jpg');
  }

  Future<void> _notifyResidentForVisitor({
    required String societyId,
    required String flatNo,
    required String visitorId,
    required String visitorType,
    required String visitorPhone,
  }) async {
    try {
      final api = ApiClient();
      final normalizedFlatNo = flatNo.trim().toUpperCase();

      final response = await api.post(
        "/api/visitors/notify-resident",
        data: {
          "society_id": societyId.trim(),
          "flat_no": normalizedFlatNo,
          // Firestore flow currently doesn't keep a separate flat_id.
          "flat_id": normalizedFlatNo,
          "visitor_id": visitorId,
          "visitor_type": visitorType.trim().toUpperCase(),
          "visitor_phone": visitorPhone.trim(),
          "status": "PENDING",
        },
      );

      AppLogger.i("Visitor resident notification requested", data: {
        "visitorId": visitorId,
        "statusCode": response.statusCode,
        "societyId": societyId,
        "flatNo": normalizedFlatNo,
      });
    } catch (e, stackTrace) {
      // Best-effort call: do not fail visitor creation if push fails.
      AppLogger.w("Failed to trigger visitor resident notification", data: {
        "visitorId": visitorId,
        "societyId": societyId,
        "flatNo": flatNo.trim().toUpperCase(),
        "error": e.toString(),
      });
      AppLogger.d("Visitor notify stack", data: {"stack": stackTrace.toString()});
    }
  }

  Future<Result<Visitor>> createVisitorWithPhoto({
    required String societyId,
    required String flatNo,
    required String visitorType,
    required String visitorPhone,
    required File photoFile,
    String? residentPhone,
    String? visitorName,
    String? deliveryPartner,
    String? deliveryPartnerOther,
    String? vehicleNumber,
    Map<String, dynamic>? typePayload,
  }) async {
    try {
      final uid = currentUid;
      if (uid == null) {
        final err = AppError(
          userMessage: "Please log in to create visitor entries",
          technicalMessage: "FirebaseAuth.currentUser is null",
        );
        AppLogger.e("createVisitorWithPhoto: No authenticated user", error: err.technicalMessage);
        return Result.failure(err);
      }

      AppLogger.i("Creating visitor with photo", data: {
        "societyId": societyId,
        "flatNo": flatNo,
        "visitorType": visitorType,
        "guardUid": uid,
      });

      final visitorId = _uuid.v4();
      AppLogger.d("Generated visitor ID", data: {"visitorId": visitorId});

      // 3) Upload photo to Firebase Storage (FIXED)
      final photoRef = _visitorPhotoRef(societyId, visitorId);
      final fileSize = await photoFile.length();

      AppLogger.i("Uploading photo to Firebase Storage", data: {
        "path": photoRef.fullPath,
        "fileSize": fileSize,
      });

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'societyId': societyId,
          'visitorId': visitorId,
          'uploadedBy': uid,
        },
      );

      // ✅ Correct: Await the UploadTask itself -> returns TaskSnapshot
      final TaskSnapshot snapshot = await photoRef
          .putFile(photoFile, metadata)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw FirebaseException(
                plugin: 'firebase_storage',
                code: 'storage/timeout',
                message: 'Upload timed out after 60 seconds',
              );
            },
          );

      AppLogger.i("Photo upload completed", data: {
        "bytesTransferred": snapshot.bytesTransferred,
        "totalBytes": snapshot.totalBytes,
        "state": snapshot.state.toString(),
        "path": snapshot.ref.fullPath,
      });

      // ✅ Correct: get URL from the uploaded ref
      final String photoUrl = await snapshot.ref.getDownloadURL();
      AppLogger.i("Photo download URL retrieved", data: {"photoUrl": photoUrl});

      // 5) Create Firestore document
      final now = FieldValue.serverTimestamp();
      final isDelivery = visitorType.toUpperCase() == 'DELIVERY';
      final visitorData = <String, dynamic>{
        "visitor_id": visitorId,
        "society_id": societyId,
        "flat_no": flatNo.trim().toUpperCase(),
        "visitor_type": visitorType.toUpperCase(),
        "visitor_phone": visitorPhone.trim(),
        "guard_uid": uid,
        "status": "PENDING",
        "photo_url": photoUrl,
        "createdAt": now,
        "updatedAt": now,
        "entry_mode": "walk_in",
        if (visitorName != null && visitorName.isNotEmpty) "visitor_name": visitorName.trim(),
        if (vehicleNumber != null && vehicleNumber.isNotEmpty) "vehicle_number": vehicleNumber.trim(),
        if (isDelivery && deliveryPartner != null && deliveryPartner.isNotEmpty) "delivery_partner": deliveryPartner.trim(),
        if (isDelivery && deliveryPartnerOther != null && deliveryPartnerOther.isNotEmpty) "delivery_partner_other": deliveryPartnerOther.trim(),
      };
      if (typePayload != null && typePayload.isNotEmpty) {
        visitorData.addAll(typePayload);
      }

      final visitorRef = _visitorsRef(societyId).doc(visitorId);
      await visitorRef.set(visitorData);
      await _notifyResidentForVisitor(
        societyId: societyId,
        flatNo: flatNo,
        visitorId: visitorId,
        visitorType: visitorType,
        visitorPhone: visitorPhone,
      );

      AppLogger.i("Visitor document created in Firestore", data: {
        "visitorId": visitorId,
        "societyId": societyId,
      });

      final createdDoc = await visitorRef.get();
      final createdData = createdDoc.data() as Map<String, dynamic>;

      DateTime createdAt;
      if (createdData['createdAt'] is Timestamp) {
        createdAt = (createdData['createdAt'] as Timestamp).toDate();
      } else {
        createdAt = DateTime.now();
      }

      final visitor = Visitor(
        visitorId: visitorId,
        societyId: societyId,
        flatId: flatNo.trim().toUpperCase(),
        flatNo: flatNo.trim().toUpperCase(),
        visitorType: visitorType.toUpperCase(),
        visitorPhone: visitorPhone.trim(),
        status: "PENDING",
        createdAt: createdAt,
        guardId: uid,
        photoUrl: photoUrl,
        residentPhone: residentPhone?.trim().isNotEmpty == true ? residentPhone!.trim() : null,
        cab: createdData['cab'] is Map ? Map<String, dynamic>.from(createdData['cab'] as Map) : null,
        delivery: createdData['delivery'] is Map ? Map<String, dynamic>.from(createdData['delivery'] as Map) : null,
      );

      return Result.success(visitor);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("createVisitorWithPhoto FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to create visitor entry",
        technicalMessage: e.toString(),
      );
      AppLogger.e("createVisitorWithPhoto unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  Future<Result<Visitor>> createVisitor({
    required String societyId,
    required String flatNo,
    required String visitorType,
    required String visitorPhone,
    String? residentPhone,
    String? visitorName,
    String? deliveryPartner,
    String? deliveryPartnerOther,
    String? vehicleNumber,
    Map<String, dynamic>? typePayload,
  }) async {
    try {
      final uid = currentUid;
      if (uid == null) {
        final err = AppError(
          userMessage: "Please log in to create visitor entries",
          technicalMessage: "FirebaseAuth.currentUser is null",
        );
        AppLogger.e("createVisitor: No authenticated user", error: err.technicalMessage);
        return Result.failure(err);
      }

      AppLogger.i("Creating visitor (no photo)", data: {
        "societyId": societyId,
        "flatNo": flatNo,
        "visitorType": visitorType,
        "guardUid": uid,
      });

      final visitorId = _uuid.v4();
      AppLogger.d("Generated visitor ID", data: {"visitorId": visitorId});

      final now = FieldValue.serverTimestamp();
      final isDelivery = visitorType.toUpperCase() == 'DELIVERY';
      final visitorData = <String, dynamic>{
        "visitor_id": visitorId,
        "society_id": societyId,
        "flat_no": flatNo.trim().toUpperCase(),
        "visitor_type": visitorType.toUpperCase(),
        "visitor_phone": visitorPhone.trim(),
        "guard_uid": uid,
        "status": "PENDING",
        "createdAt": now,
        "updatedAt": now,
        "entry_mode": "walk_in",
        if (residentPhone != null && residentPhone.isNotEmpty) "resident_phone": residentPhone.trim(),
        if (visitorName != null && visitorName.isNotEmpty) "visitor_name": visitorName.trim(),
        if (vehicleNumber != null && vehicleNumber.isNotEmpty) "vehicle_number": vehicleNumber.trim(),
        if (isDelivery && deliveryPartner != null && deliveryPartner.isNotEmpty) "delivery_partner": deliveryPartner.trim(),
        if (isDelivery && deliveryPartnerOther != null && deliveryPartnerOther.isNotEmpty) "delivery_partner_other": deliveryPartnerOther.trim(),
      };
      if (typePayload != null && typePayload.isNotEmpty) {
        visitorData.addAll(typePayload);
      }

      final visitorRef = _visitorsRef(societyId).doc(visitorId);
      await visitorRef.set(visitorData);
      await _notifyResidentForVisitor(
        societyId: societyId,
        flatNo: flatNo,
        visitorId: visitorId,
        visitorType: visitorType,
        visitorPhone: visitorPhone,
      );

      AppLogger.i("Visitor document created in Firestore", data: {
        "visitorId": visitorId,
        "societyId": societyId,
      });

      final createdDoc = await visitorRef.get();
      final createdData = createdDoc.data() as Map<String, dynamic>;

      DateTime createdAt;
      if (createdData['createdAt'] is Timestamp) {
        createdAt = (createdData['createdAt'] as Timestamp).toDate();
      } else {
        createdAt = DateTime.now();
      }

      final visitor = Visitor(
        visitorId: visitorId,
        societyId: societyId,
        flatId: flatNo.trim().toUpperCase(),
        flatNo: flatNo.trim().toUpperCase(),
        visitorType: visitorType.toUpperCase(),
        visitorPhone: visitorPhone.trim(),
        status: "PENDING",
        createdAt: createdAt,
        guardId: uid,
        residentPhone: residentPhone?.trim().isNotEmpty == true ? residentPhone!.trim() : null,
        cab: createdData['cab'] is Map ? Map<String, dynamic>.from(createdData['cab'] as Map) : null,
        delivery: createdData['delivery'] is Map ? Map<String, dynamic>.from(createdData['delivery'] as Map) : null,
      );

      return Result.success(visitor);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("createVisitor FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to create visitor entry",
        technicalMessage: e.toString(),
      );
      AppLogger.e("createVisitor unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  AppError _mapFirebaseError(FirebaseException e) {
    String userMessage = "Firebase error. Please try again.";

    switch (e.code) {
      case 'permission-denied':
        userMessage = "Permission denied. Please check your access.";
        break;
      case 'unauthenticated':
        userMessage = "Please log in to continue.";
        break;
      case 'storage/unauthorized':
        userMessage = "Storage permission denied.";
        break;
      case 'storage/canceled':
        userMessage = "Upload was canceled. Please try again.";
        break;
      case 'storage/unknown':
        userMessage = "Storage error. Please try again.";
        break;
      case 'storage/object-not-found':
        userMessage = "Photo upload failed. Please try again.";
        break;
      case 'upload-failed':
        userMessage = "Photo upload failed. Please try again.";
        break;
      case 'upload-error':
        userMessage = "Photo upload error. Please try again.";
        break;
      case 'storage/timeout':
        userMessage = "Upload timed out. Please check your connection and try again.";
        break;
      case 'unavailable':
        userMessage = "Service unavailable. Please check your connection.";
        break;
      default:
        if (e.code.startsWith('storage/')) {
          userMessage = "Storage error: ${e.message ?? 'Please try again'}";
        } else {
          userMessage = "Error: ${e.message ?? 'Unknown error'}";
        }
    }

    final technical = "FirebaseException(code=${e.code}, message=${e.message})";
    return AppError(userMessage: userMessage, technicalMessage: technical);
  }

  /// Get pending approvals for a flat (one-time get, scoped to society).
  /// Returns list of visitors with status = "PENDING" for the given flat_no.
  /// Limit 50 to avoid loading too many at once.
  Future<Result<List<Map<String, dynamic>>>> getPendingApprovals({
    required String societyId,
    required String flatNo,
  }) async {
    try {
      final visitorsRef = _visitorsRef(societyId);
      final normalizedFlatNo = flatNo.trim().toUpperCase();
      
      AppLogger.i("Fetching pending approvals", data: {
        "societyId": societyId,
        "flatNo": normalizedFlatNo,
      });

      final querySnapshot = await visitorsRef
          .where('flat_no', isEqualTo: normalizedFlatNo)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final List<Map<String, dynamic>> visitors = [];
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Convert Firestore Timestamp to ISO string for compatibility
        DateTime createdAt;
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }
        
        // Format data to match backend API response format
        visitors.add({
          'visitor_id': data['visitor_id'] ?? doc.id,
          'society_id': data['society_id'] ?? societyId,
          'flat_no': data['flat_no'] ?? normalizedFlatNo,
          'visitor_type': data['visitor_type'] ?? 'GUEST',
          'visitor_phone': data['visitor_phone'] ?? '',
          'status': data['status'] ?? 'PENDING',
          'created_at': createdAt.toIso8601String(),
          'guard_id': data['guard_uid'] ?? '',
          'photo_url': data['photo_url'],
        });
      }

      AppLogger.i("Found ${visitors.length} pending approvals");
      return Result.success(visitors);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("getPendingApprovals FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to load approvals",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getPendingApprovals unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Update visitor status (approve/reject)
  Future<Result<Map<String, dynamic>>> updateVisitorStatus({
    required String societyId,
    required String visitorId,
    required String status, // "APPROVED" | "REJECTED"
    required String residentId,
    String note = "",
  }) async {
    try {
      if (status != "APPROVED" && status != "REJECTED") {
        return Result.failure(AppError(
          userMessage: "Invalid status. Must be APPROVED or REJECTED",
          technicalMessage: "Invalid status: $status",
        ));
      }

      final visitorRef = _visitorsRef(societyId).doc(visitorId);
      
      // Check if visitor exists
      final visitorDoc = await visitorRef.get();
      if (!visitorDoc.exists) {
        return Result.failure(AppError(
          userMessage: "Visitor not found",
          technicalMessage: "Visitor $visitorId not found in society $societyId",
        ));
      }

      final now = FieldValue.serverTimestamp();
      await visitorRef.update({
        'status': status,
        'approved_at': now,
        'approved_by': residentId,
        'note': note,
        'updatedAt': now,
      });

      AppLogger.i("Visitor status updated", data: {
        "visitorId": visitorId,
        "status": status,
        "residentId": residentId,
      });

      return Result.success({
        'visitor_id': visitorId,
        'status': status,
        'updated': true,
      });
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("updateVisitorStatus FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to update visitor status",
        technicalMessage: e.toString(),
      );
      AppLogger.e("updateVisitorStatus unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Get visitor history (APPROVED/REJECTED) for a flat
  /// Returns list of visitors with status = "APPROVED" or "REJECTED" for the given flat_no
  Future<Result<List<Map<String, dynamic>>>> getHistory({
    required String societyId,
    required String flatNo,
    int limit = 100,
  }) async {
    try {
      final visitorsRef = _visitorsRef(societyId);
      final normalizedFlatNo = flatNo.trim().toUpperCase();
      
      AppLogger.i("Fetching visitor history", data: {
        "societyId": societyId,
        "flatNo": normalizedFlatNo,
        "limit": limit,
      });

      // Query for APPROVED or REJECTED visitors
      // Note: Using whereIn with orderBy requires a composite index
      // To avoid index requirement, we query without orderBy and sort in memory
      final querySnapshot = await visitorsRef
          .where('flat_no', isEqualTo: normalizedFlatNo)
          .where('status', whereIn: ['APPROVED', 'REJECTED'])
          .get();
      
      // Sort in memory by createdAt descending and limit
      final sortedDocs = querySnapshot.docs.toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime); // Descending order
        });
      
      final limitedDocs = sortedDocs.take(limit).toList();

      final List<Map<String, dynamic>> visitors = [];
      
      for (var doc in limitedDocs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Convert Firestore Timestamp to ISO string for compatibility
        DateTime createdAt;
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }

        DateTime? approvedAt;
        if (data['approved_at'] is Timestamp) {
          approvedAt = (data['approved_at'] as Timestamp).toDate();
        }
        
        // Format data to match backend API response format (include delivery/visitor name for resident UI)
        visitors.add({
          'visitor_id': data['visitor_id'] ?? doc.id,
          'society_id': data['society_id'] ?? societyId,
          'flat_no': data['flat_no'] ?? normalizedFlatNo,
          'visitor_type': data['visitor_type'] ?? 'GUEST',
          'visitor_phone': data['visitor_phone'] ?? '',
          'visitor_name': data['visitor_name'],
          'delivery_partner': data['delivery_partner'],
          'delivery_partner_other': data['delivery_partner_other'],
          'status': data['status'] ?? '',
          'created_at': createdAt.toIso8601String(),
          'approved_at': approvedAt?.toIso8601String(),
          'approved_by': data['approved_by'],
          'guard_id': data['guard_uid'] ?? '',
          'photo_url': data['photo_url'],
          'note': data['note'],
        });
      }

      AppLogger.i("Found ${visitors.length} history entries");
      return Result.success(visitors);
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("getHistory FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      final err = AppError(
        userMessage: "Failed to load history",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getHistory unknown error", error: err.technicalMessage, stackTrace: stackTrace);
      return Result.failure(err);
    }
  }

  /// Paginated resident history: one-time get(), scoped to society.
  /// Uses orderBy(createdAt, descending) + limit + startAfterDocument for "Load more".
  /// Returns { 'visitors': List<Map>, 'lastDoc': DocumentSnapshot? } for next page.
  /// Requires composite index: flat_no (==), status (in), createdAt (desc).
  Future<Result<Map<String, dynamic>>> getHistoryPage({
    required String societyId,
    required String flatNo,
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final visitorsRef = _visitorsRef(societyId);
      final normalizedFlatNo = flatNo.trim().toUpperCase();

      final baseQuery = visitorsRef
          .where('flat_no', isEqualTo: normalizedFlatNo)
          .where('status', whereIn: ['APPROVED', 'REJECTED'])
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final querySnapshot = startAfter == null
          ? await baseQuery.get()
          : await baseQuery.startAfterDocument(startAfter).get();

      final List<Map<String, dynamic>> visitors = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        DateTime createdAt;
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }
        DateTime? approvedAt;
        if (data['approved_at'] is Timestamp) {
          approvedAt = (data['approved_at'] as Timestamp).toDate();
        }
        visitors.add({
          'visitor_id': data['visitor_id'] ?? doc.id,
          'society_id': data['society_id'] ?? societyId,
          'flat_no': data['flat_no'] ?? normalizedFlatNo,
          'visitor_type': data['visitor_type'] ?? 'GUEST',
          'visitor_phone': data['visitor_phone'] ?? '',
          'visitor_name': data['visitor_name'],
          'delivery_partner': data['delivery_partner'],
          'delivery_partner_other': data['delivery_partner_other'],
          'status': data['status'] ?? '',
          'created_at': createdAt.toIso8601String(),
          'approved_at': approvedAt?.toIso8601String(),
          'approved_by': data['approved_by'],
          'guard_id': data['guard_uid'] ?? '',
          'photo_url': data['photo_url'],
          'note': data['note'],
        });
      }

      final DocumentSnapshot? lastDoc = querySnapshot.docs.isEmpty
          ? null
          : querySnapshot.docs.last;

      return Result.success({
        'visitors': visitors,
        'lastDoc': lastDoc,
      });
    } on FirebaseException catch (e) {
      final err = _mapFirebaseError(e);
      AppLogger.e("getHistoryPage FirebaseException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e, stackTrace) {
      AppLogger.e("getHistoryPage unknown error", error: e, stackTrace: stackTrace);
      return Result.failure(AppError(
        userMessage: "Failed to load history",
        technicalMessage: e.toString(),
      ));
    }
  }

  // --- Admin Insights Lite: today's visitor counts (efficient, count aggregate when supported) ---

  /// Start of today (00:00) in local time. [referenceDate] allows tests to fix the "today" boundary.
  static DateTime _startOfDay([DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Total visitors created today (createdAt >= start of day). Safe for large collections (uses count aggregate).
  Future<int> getVisitorCountToday(String societyId, {DateTime? referenceDate}) async {
    try {
      final start = _startOfDay(referenceDate);
      final ts = Timestamp.fromDate(start);
      final snapshot = await _visitorsRef(societyId)
          .where('createdAt', isGreaterThanOrEqualTo: ts)
          .count()
          .get();
      return snapshot.count ?? 0;
    } on FirebaseException catch (e) {
      AppLogger.e('getVisitorCountToday FirebaseException', error: e.message);
      return 0;
    } catch (e) {
      AppLogger.e('getVisitorCountToday', error: e);
      return 0;
    }
  }

  /// Pending visitors today (status == PENDING, createdAt >= start of day).
  Future<int> getPendingVisitorCountToday(String societyId, {DateTime? referenceDate}) async {
    try {
      final start = _startOfDay(referenceDate);
      final ts = Timestamp.fromDate(start);
      final snapshot = await _visitorsRef(societyId)
          .where('createdAt', isGreaterThanOrEqualTo: ts)
          .where('status', isEqualTo: 'PENDING')
          .count()
          .get();
      return snapshot.count ?? 0;
    } on FirebaseException catch (e) {
      AppLogger.e('getPendingVisitorCountToday FirebaseException', error: e.message);
      return 0;
    } catch (e) {
      AppLogger.e('getPendingVisitorCountToday', error: e);
      return 0;
    }
  }

  /// Cab visitors today (visitor_type == CAB, createdAt >= start of day). Uses visitor_type for index-friendly query.
  Future<int> getCabVisitorCountToday(String societyId, {DateTime? referenceDate}) async {
    try {
      final start = _startOfDay(referenceDate);
      final ts = Timestamp.fromDate(start);
      final snapshot = await _visitorsRef(societyId)
          .where('createdAt', isGreaterThanOrEqualTo: ts)
          .where('visitor_type', isEqualTo: 'CAB')
          .count()
          .get();
      return snapshot.count ?? 0;
    } on FirebaseException catch (e) {
      AppLogger.e('getCabVisitorCountToday FirebaseException', error: e.message);
      return 0;
    } catch (e) {
      AppLogger.e('getCabVisitorCountToday', error: e);
      return 0;
    }
  }

  /// Delivery visitors today (visitor_type == DELIVERY, createdAt >= start of day). Uses visitor_type for index-friendly query.
  Future<int> getDeliveryVisitorCountToday(String societyId, {DateTime? referenceDate}) async {
    try {
      final start = _startOfDay(referenceDate);
      final ts = Timestamp.fromDate(start);
      final snapshot = await _visitorsRef(societyId)
          .where('createdAt', isGreaterThanOrEqualTo: ts)
          .where('visitor_type', isEqualTo: 'DELIVERY')
          .count()
          .get();
      return snapshot.count ?? 0;
    } on FirebaseException catch (e) {
      AppLogger.e('getDeliveryVisitorCountToday FirebaseException', error: e.message);
      return 0;
    } catch (e) {
      AppLogger.e('getDeliveryVisitorCountToday', error: e);
      return 0;
    }
  }
}
