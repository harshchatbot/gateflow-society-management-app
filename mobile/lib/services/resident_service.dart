import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

class ResidentService {
  // ✅ Change this if you already have a baseUrl in dotenv/service
  final String baseUrl;

  ResidentService({required this.baseUrl});

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse("$baseUrl$path").replace(queryParameters: query);
  }

  Future<ApiResult<Map<String, dynamic>>> getProfile({
    required String societyId,
    required String flatNo,
    String? phone,
  }) async {
    try {
      final query = <String, String>{
        "society_id": societyId,
        "flat_no": flatNo,
      };
      if (phone != null && phone.trim().isNotEmpty) {
        query["phone"] = phone.trim();
      }

      final res = await http.get(_uri("/api/residents/profile", query));
      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Profile failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("getProfile error: $e");
      return ApiResult.failure("Connection error");
    }
  }

  Future<ApiResult<List<dynamic>>> getApprovals({
    required String societyId,
    required String flatNo,
  }) async {
    try {
      final res = await http.get(_uri("/api/residents/approvals", {
        "society_id": societyId,
        "flat_no": flatNo,
      }));
      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.failure("Approvals failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("getApprovals error: $e");
      return ApiResult.failure("Connection error");
    }
  }

  Future<ApiResult<List<dynamic>>> getHistory({
    required String societyId,
    required String flatNo,
    int limit = 50,
  }) async {
    try {
      final res = await http.get(_uri("/api/residents/history", {
        "society_id": societyId,
        "flat_no": flatNo,
        "limit": "$limit",
      }));
      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.failure("History failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("getHistory error: $e");
      return ApiResult.failure("Connection error");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> decide({
    required String societyId,
    required String flatNo,
    required String residentId,
    required String visitorId,
    required String decision, // "APPROVED" | "REJECTED"
    String note = "",
  }) async {
    try {
      final body = jsonEncode({
        "society_id": societyId,
        "flat_no": flatNo,
        "resident_id": residentId,
        "visitor_id": visitorId,
        "decision": decision,
        "note": note,
      });

      final res = await http.post(
        _uri("/api/residents/decision"),
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Decision failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("decide error: $e");
      return ApiResult.failure("Connection error");
    }
  }
}
