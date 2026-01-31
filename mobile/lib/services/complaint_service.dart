import 'dart:async';
import '../core/app_logger.dart';
import '../core/storage.dart';
import 'firestore_service.dart';

class ApiResult<T> {
  final bool isSuccess;
  final T? data;
  final String? error;

  ApiResult.success(this.data)
      : isSuccess = true,
        error = null;

  ApiResult.failure(this.error)
      : isSuccess = false,
        data = null;
}

class ComplaintService {
  final String baseUrl; // Kept for backward compatibility, not used
  final FirestoreService _firestore = FirestoreService();

  ComplaintService({required this.baseUrl});

  Future<ApiResult<Map<String, dynamic>>> createComplaint({
    required String societyId,
    required String flatNo,
    required String residentId,
    required String residentName,
    required String title,
    required String description,
    required String category,
    /// 'general' = visible to everyone; 'personal' = visible to admins & guards only
    String visibility = 'general',
    /// Optional image URL (e.g. uploaded to Firebase Storage)
    String? photoUrl,
  }) async {
    try {
      // Get current user UID
      final session = await Storage.getFirebaseSession();
      if (session == null || session['uid'] == null) {
        return ApiResult.failure("User not authenticated");
      }
      final uid = session['uid'] as String;

      final complaintId = await _firestore.createComplaint(
        societyId: societyId,
        flatNo: flatNo,
        residentUid: uid,
        residentName: residentName,
        category: category,
        title: title,
        description: description,
        visibility: visibility,
        photoUrl: photoUrl,
      );

      AppLogger.i("Complaint created successfully", data: {'complaintId': complaintId});

      return ApiResult.success({
        'complaint_id': complaintId,
        'society_id': societyId,
        'flat_no': flatNo,
        'resident_id': residentId,
        'resident_name': residentName,
        'title': title,
        'description': description,
        'category': category,
        'status': 'pending',
      });
    } catch (e, stackTrace) {
      AppLogger.e("Error creating complaint", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to create complaint: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getResidentComplaints({
    required String societyId,
    required String flatNo,
    String? residentId,
  }) async {
    try {
      final session = await Storage.getFirebaseSession();
      String? residentUid;
      if (session != null && session['uid'] != null) {
        residentUid = session['uid'] as String;
      }

      final complaints = await _firestore.getResidentComplaints(
        societyId: societyId,
        flatNo: flatNo,
        residentUid: residentUid,
      );

      AppLogger.i("Resident complaints fetched", data: {'count': complaints.length});
      return ApiResult.success(complaints);
    } catch (e, stackTrace) {
      AppLogger.e("Error getting resident complaints", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to load complaints: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getAllComplaints({
    required String societyId,
    String? status,
  }) async {
    try {
      final complaints = await _firestore.getAllComplaints(
        societyId: societyId,
        status: status,
      );

      AppLogger.i("All complaints fetched", data: {'count': complaints.length});
      return ApiResult.success(complaints);
    } catch (e, stackTrace) {
      AppLogger.e("Error getting all complaints", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to load complaints: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> updateComplaintStatus({
    required String complaintId,
    required String status,
    String? resolvedBy,
    String? adminResponse,
  }) async {
    try {
      final session = await Storage.getFirebaseSession();
      if (session == null || session['societyId'] == null || session['uid'] == null) {
        return ApiResult.failure("User not authenticated");
      }
      final societyId = session['societyId'] as String;
      final uid = session['uid'] as String;
      final name = session['name'] as String? ?? 'Admin';

      await _firestore.updateComplaintStatus(
        societyId: societyId,
        complaintId: complaintId,
        status: status,
        resolvedByUid: resolvedBy ?? uid,
        resolvedByName: resolvedBy != null ? resolvedBy : name,
        adminResponse: adminResponse,
      );

      AppLogger.i("Complaint status updated", data: {'complaintId': complaintId, 'status': status});
      return ApiResult.success({
        'ok': true,
        'complaint_id': complaintId,
        'status': status,
      });
    } catch (e, stackTrace) {
      AppLogger.e("Error updating complaint status", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to update complaint: ${e.toString()}");
    }
  }
}
