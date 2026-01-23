import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class NoticeService {
  final String baseUrl; // Kept for backward compatibility, not used
  final FirestoreService _firestore = FirestoreService();

  NoticeService({required this.baseUrl});

  Future<ApiResult<Map<String, dynamic>>> createNotice({
    required String societyId,
    required String adminId,
    required String adminName,
    required String title,
    required String content,
    required String noticeType,
    required String priority,
    String? expiryDate,
  }) async {
    try {
      // Get current user UID
      final session = await Storage.getFirebaseSession();
      if (session == null || session['uid'] == null) {
        return ApiResult.failure("User not authenticated");
      }
      final uid = session['uid'] as String;

      // Parse expiry date if provided
      Timestamp? expiryAt;
      if (expiryDate != null && expiryDate.isNotEmpty) {
        try {
          final expiry = DateTime.parse(expiryDate);
          expiryAt = Timestamp.fromDate(expiry);
        } catch (e) {
          AppLogger.w("Invalid expiry date format", data: {'expiryDate': expiryDate});
        }
      }

      final noticeId = await _firestore.createNotice(
        societyId: societyId,
        title: title,
        content: content,
        noticeType: noticeType,
        priority: priority,
        createdByUid: uid,
        createdByName: adminName,
        expiryAt: expiryAt,
      );

      AppLogger.i("Notice created successfully", data: {'noticeId': noticeId});

      return ApiResult.success({
        'notice_id': noticeId,
        'society_id': societyId,
        'title': title,
        'content': content,
        'notice_type': noticeType,
        'priority': priority,
        'status': 'active',
      });
    } catch (e, stackTrace) {
      AppLogger.e("Error creating notice", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to create notice: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getNotices({
    required String societyId,
    bool activeOnly = true,
  }) async {
    try {
      // Get current user's system role for filtering
      final session = await Storage.getFirebaseSession();
      String? targetRole;
      if (session != null) {
        final systemRole = session['systemRole'] as String?;
        if (systemRole != null) {
          targetRole = systemRole; // "admin" | "guard" | "resident"
        }
      }

      final notices = await _firestore.getNotices(
        societyId: societyId,
        activeOnly: activeOnly,
        targetRole: targetRole,
      );

      AppLogger.i("Notices fetched successfully", data: {'count': notices.length});
      return ApiResult.success(notices);
    } catch (e, stackTrace) {
      AppLogger.e("Error getting notices", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to load notices: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> updateNoticeStatus({
    required String noticeId,
    required bool isActive,
  }) async {
    try {
      final session = await Storage.getFirebaseSession();
      if (session == null || session['societyId'] == null) {
        return ApiResult.failure("User not authenticated");
      }
      final societyId = session['societyId'] as String;

      await _firestore.updateNoticeStatus(
        societyId: societyId,
        noticeId: noticeId,
        isActive: isActive,
      );

      AppLogger.i("Notice status updated", data: {'noticeId': noticeId, 'isActive': isActive});
      return ApiResult.success({'ok': true, 'notice_id': noticeId, 'is_active': isActive});
    } catch (e, stackTrace) {
      AppLogger.e("Error updating notice status", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to update notice: ${e.toString()}");
    }
  }

  Future<ApiResult<bool>> deleteNotice({
    required String noticeId,
  }) async {
    try {
      final session = await Storage.getFirebaseSession();
      if (session == null || session['societyId'] == null) {
        return ApiResult.failure("User not authenticated");
      }
      final societyId = session['societyId'] as String;

      await _firestore.deleteNotice(
        societyId: societyId,
        noticeId: noticeId,
      );

      AppLogger.i("Notice deleted", data: {'noticeId': noticeId});
      return ApiResult.success(true);
    } catch (e, stackTrace) {
      AppLogger.e("Error deleting notice", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to delete notice: ${e.toString()}");
    }
  }
}
