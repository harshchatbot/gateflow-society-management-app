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

class ComplaintService {
  final String baseUrl;

  ComplaintService({required this.baseUrl});

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse("$baseUrl$path").replace(queryParameters: query);
  }

  Future<ApiResult<Map<String, dynamic>>> createComplaint({
    required String societyId,
    required String flatNo,
    required String residentId,
    required String residentName,
    required String title,
    required String description,
    required String category,
  }) async {
    try {
      final body = jsonEncode({
        "society_id": societyId,
        "flat_no": flatNo,
        "resident_id": residentId,
        "resident_name": residentName,
        "title": title,
        "description": description,
        "category": category,
      });

      AppLogger.i("Create complaint request", data: {
        "society_id": societyId,
        "flat_no": flatNo,
        "title": title,
        "category": category,
      });

      final res = await http
          .post(
            _uri("/api/complaints"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Create complaint response", data: {"status": res.statusCode, "body": res.body});

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Failed to create complaint: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Create complaint timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Create complaint socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Create complaint error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getResidentComplaints({
    required String societyId,
    required String flatNo,
    String? residentId,
  }) async {
    try {
      final query = <String, String>{
        "society_id": societyId,
        "flat_no": flatNo,
      };
      if (residentId != null && residentId.isNotEmpty) {
        query["resident_id"] = residentId;
      }

      final uri = _uri("/api/complaints/resident", query);
      AppLogger.i("Get resident complaints request", data: query);

      final res = await http.get(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.failure("Failed to load complaints: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Get complaints timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Get complaints socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Get complaints error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getAllComplaints({
    required String societyId,
    String? status,
  }) async {
    try {
      final query = <String, String>{
        "society_id": societyId,
      };
      if (status != null && status.isNotEmpty) {
        query["status"] = status;
      }

      final uri = _uri("/api/complaints/admin", query);
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.failure("Failed to load complaints: ${res.statusCode}");
    } catch (e) {
      AppLogger.e("Get all complaints error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> updateComplaintStatus({
    required String complaintId,
    required String status,
    String? resolvedBy,
    String? adminResponse,
  }) async {
    try {
      final body = jsonEncode({
        "status": status,
        if (resolvedBy != null) "resolved_by": resolvedBy,
        if (adminResponse != null) "admin_response": adminResponse,
      });

      final res = await http
          .put(
            _uri("/api/complaints/$complaintId/status"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Failed to update complaint: ${res.statusCode}");
    } catch (e) {
      AppLogger.e("Update complaint status error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }
}
