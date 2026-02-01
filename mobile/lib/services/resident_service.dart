import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'firebase_visitor_service.dart';

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
  final FirebaseVisitorService _firebaseVisitorService = FirebaseVisitorService();

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

      final uri = _uri("/api/residents/profile", query);
      debugPrint("ResidentService.getProfile: Requesting $uri");

      final res = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint("ResidentService.getProfile: Request timeout");
          throw TimeoutException("Request timeout after 10 seconds");
        },
      );

      debugPrint("ResidentService.getProfile: Response status ${res.statusCode}, body: ${res.body}");

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      } else if (res.statusCode == 404) {
        return ApiResult.failure("Resident not found. Please check Society ID and Flat No.");
      } else if (res.statusCode == 401) {
        return ApiResult.failure("Unauthorized. Please check your phone number.");
      } else {
        return ApiResult.failure("Profile failed: ${res.statusCode} ${res.body}");
      }
    } on TimeoutException catch (e) {
      debugPrint("getProfile timeout error: $e");
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      debugPrint("getProfile socket error: $e");
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      debugPrint("getProfile error: $e");
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getApprovals({
    required String societyId,
    required String flatNo,
  }) async {
    try {
      // Use Firebase directly instead of backend API
      final result = await _firebaseVisitorService.getPendingApprovals(
        societyId: societyId,
        flatNo: flatNo,
      );
      
      if (result.isSuccess && result.data != null) {
        return ApiResult.success(result.data!);
      } else {
        return ApiResult.failure(result.error?.userMessage ?? "Failed to load approvals");
      }
    } catch (e) {
      debugPrint("getApprovals error: $e");
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  /// One-time fetch of first page of history (for dashboard/stats).
  /// Returns list of visitors only; for full pagination use getHistoryPage.
  Future<ApiResult<List<dynamic>>> getHistory({
    required String societyId,
    required String flatNo,
    int limit = 100,
  }) async {
    try {
      final result = await _firebaseVisitorService.getHistoryPage(
        societyId: societyId,
        flatNo: flatNo,
        limit: limit,
        startAfter: null,
      );
      if (result.isSuccess && result.data != null) {
        final list = result.data!['visitors'] as List<dynamic>? ?? [];
        return ApiResult.success(list);
      }
      return ApiResult.failure(result.error?.userMessage ?? "Failed to load history");
    } catch (e) {
      debugPrint("getHistory error: $e");
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  /// Paginated history: first page use startAfter: null, next pages pass lastDoc.
  /// Returns { 'visitors': List<Map>, 'lastDoc': DocumentSnapshot? }.
  Future<ApiResult<Map<String, dynamic>>> getHistoryPage({
    required String societyId,
    required String flatNo,
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final result = await _firebaseVisitorService.getHistoryPage(
        societyId: societyId,
        flatNo: flatNo,
        limit: limit,
        startAfter: startAfter,
      );
      if (result.isSuccess && result.data != null) {
        return ApiResult.success(result.data!);
      }
      return ApiResult.failure(result.error?.userMessage ?? "Failed to load history");
    } catch (e) {
      debugPrint("getHistoryPage error: $e");
      return ApiResult.failure("Connection error: ${e.toString()}");
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
      // Use Firebase directly instead of backend API
      final result = await _firebaseVisitorService.updateVisitorStatus(
        societyId: societyId,
        visitorId: visitorId,
        status: decision,
        residentId: residentId,
        note: note,
      );
      
      if (result.isSuccess && result.data != null) {
        return ApiResult.success(result.data!);
      } else {
        return ApiResult.failure(result.error?.userMessage ?? "Failed to process decision");
      }
    } catch (e) {
      debugPrint("decide error: $e");
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> updateProfile({
    required String residentId,
    required String societyId,
    required String flatNo,
    String? residentName,
    String? residentPhone,
  }) async {
    try {
      final body = jsonEncode({
        "resident_id": residentId,
        "society_id": societyId,
        "flat_no": flatNo,
        if (residentName != null) "resident_name": residentName,
        if (residentPhone != null) "resident_phone": residentPhone,
      });

      final res = await http.put(
        _uri("/api/residents/profile"),
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Update failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("updateProfile error: $e");
      return ApiResult.failure("Connection error");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> uploadProfileImage({
    required String residentId,
    required String societyId,
    required String flatNo,
    required String imagePath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri("/api/residents/profile/image"),
      );

      request.fields['resident_id'] = residentId;
      request.fields['society_id'] = societyId;
      request.fields['flat_no'] = flatNo;

      final file = await http.MultipartFile.fromPath('file', imagePath);
      request.files.add(file);

      final streamedResponse = await request.send();
      final res = await http.Response.fromStream(streamedResponse);

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Upload failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("uploadProfileImage error: $e");
      return ApiResult.failure("Connection error");
    }
  }

  /// Trigger SOS push notification via FastAPI backend.
  /// Firestore already stores the SOS record; this call only sends FCM to staff.
  Future<ApiResult<void>> sendSosAlert({
    required String societyId,
    required String flatNo,
    required String residentName,
    String? residentPhone,
    String? sosId,
  }) async {
    try {
      final uri = _uri("/api/residents/sos");
      final body = jsonEncode({
        "society_id": societyId,
        "flat_no": flatNo,
        "resident_name": residentName,
        if (residentPhone != null && residentPhone.trim().isNotEmpty)
          "resident_phone": residentPhone.trim(),
        if (sosId != null && sosId.trim().isNotEmpty)
          "sos_id": sosId.trim(),
      });

      final res = await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return ApiResult.success(null);
      }
      return ApiResult.failure("SOS notify failed: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      debugPrint("sendSosAlert timeout error: $e");
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      debugPrint("sendSosAlert socket error: $e");
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      debugPrint("sendSosAlert error: $e");
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }
}
