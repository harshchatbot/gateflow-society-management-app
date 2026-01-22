import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/app_logger.dart';

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
  final String baseUrl;

  NoticeService({required this.baseUrl});

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse("$baseUrl$path").replace(queryParameters: query);
  }

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
      final body = jsonEncode({
        "society_id": societyId,
        "admin_id": adminId,
        "admin_name": adminName,
        "title": title,
        "content": content,
        "notice_type": noticeType,
        "priority": priority,
        if (expiryDate != null) "expiry_date": expiryDate,
      });

      AppLogger.i("Create notice request", data: {
        "society_id": societyId,
        "title": title,
        "notice_type": noticeType,
        "priority": priority,
      });

      final res = await http
          .post(
            _uri("/api/notices"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Create notice response", data: {"status": res.statusCode, "body": res.body});

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Failed to create notice: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Create notice timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Create notice socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Create notice error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getNotices({
    required String societyId,
    bool activeOnly = true,
  }) async {
    try {
      final query = <String, String>{
        "society_id": societyId,
        "active_only": activeOnly.toString(),
      };

      final uri = _uri("/api/notices", query);
      AppLogger.i("Get notices request", data: {"society_id": societyId, "active_only": activeOnly, "uri": uri.toString()});

      final res = await http.get(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Get notices response", data: {"status": res.statusCode, "body_length": res.body.length});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        AppLogger.i("Get notices success", data: {"count": data.length});
        return ApiResult.success(data);
      }
      AppLogger.w("Get notices failed", data: {"status": res.statusCode, "body": res.body});
      return ApiResult.failure("Failed to load notices: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Get notices timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Get notices socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Get notices error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> updateNoticeStatus({
    required String noticeId,
    required bool isActive,
  }) async {
    try {
      final body = jsonEncode({
        "is_active": isActive,
      });

      final res = await http
          .put(
            _uri("/api/notices/$noticeId/status"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Failed to update notice: ${res.statusCode}");
    } catch (e) {
      AppLogger.e("Update notice status error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<bool>> deleteNotice({
    required String noticeId,
  }) async {
    try {
      final res = await http
          .delete(_uri("/api/notices/$noticeId"))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return ApiResult.success(true);
      }
      return ApiResult.failure("Failed to delete notice: ${res.statusCode}");
    } catch (e) {
      AppLogger.e("Delete notice error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }
}
