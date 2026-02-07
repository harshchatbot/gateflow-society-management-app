import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../core/app_logger.dart';
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

class AdminService {
  final String baseUrl;

  AdminService({required this.baseUrl});

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse("$baseUrl$path").replace(queryParameters: query);
  }

  Future<ApiResult<Map<String, dynamic>>> login({
    required String societyId,
    required String adminId,
    required String pin,
  }) async {
    try {
      final body = jsonEncode({
        "society_id": societyId,
        "admin_id": adminId,
        "pin": pin,
      });

      AppLogger.i("Admin login request", data: {"society_id": societyId, "admin_id": adminId});

      final res = await http
          .post(
            _uri("/api/admins/login"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Admin login response", data: {"status": res.statusCode, "body": res.body});

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Login failed: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Admin login timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Admin login socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Admin login error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> getStats({
    required String societyId,
  }) async {
    try {
      // Use Firestore for stats
      final firestore = FirestoreService();
      final stats = await firestore.getAdminStats(societyId: societyId);
      
      AppLogger.i("Admin stats fetched from Firestore", data: stats);
      return ApiResult.success(stats);
    } catch (e, stackTrace) {
      AppLogger.e("Admin getStats error", error: e, stackTrace: stackTrace);
      return ApiResult.failure("Failed to load stats: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getResidents({
    required String societyId,
  }) async {
    try {
      final uri = _uri("/api/admins/residents", {"society_id": societyId});
      AppLogger.i("Admin getResidents request", data: {"society_id": societyId, "uri": uri.toString()});
      
      final res = await http.get(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Admin getResidents response", data: {"status": res.statusCode, "body_length": res.body.length});

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      
      // Log the full error response for debugging
      AppLogger.e("Admin getResidents failed", data: {"status": res.statusCode, "body": res.body});
      return ApiResult.failure("Failed to load residents: ${res.statusCode} ${res.body.length > 100 ? res.body.substring(0, 100) : res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Admin getResidents timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Admin getResidents socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Admin getResidents error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getGuards({
    required String societyId,
  }) async {
    try {
      final uri = _uri("/api/admins/guards", {"society_id": societyId});
      AppLogger.i("Admin getGuards request", data: {"society_id": societyId, "uri": uri.toString()});
      
      final res = await http.get(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Admin getGuards response", data: {"status": res.statusCode, "body_length": res.body.length});

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      
      // Log the full error response for debugging
      AppLogger.e("Admin getGuards failed", data: {"status": res.statusCode, "body": res.body});
      return ApiResult.failure("Failed to load guards: ${res.statusCode} ${res.body.length > 100 ? res.body.substring(0, 100) : res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Admin getGuards timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Admin getGuards socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Admin getGuards error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getFlats({
    required String societyId,
  }) async {
    try {
      final uri = _uri("/api/admins/flats", {"society_id": societyId});
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.failure("Failed to load flats: ${res.statusCode}");
    } catch (e) {
      AppLogger.e("Admin getFlats error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<List<dynamic>>> getVisitors({
    required String societyId,
    int limit = 100,
  }) async {
    try {
      final uri = _uri("/api/admins/visitors", {
        "society_id": societyId,
        "limit": limit.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.failure("Failed to load visitors: ${res.statusCode}");
    } catch (e) {
      AppLogger.e("Admin getVisitors error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> uploadProfileImage({
    required String adminId,
    required String societyId,
    required String imagePath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri("/api/admins/profile/image"),
      );

      request.fields['admin_id'] = adminId;
      request.fields['society_id'] = societyId;

      final file = await http.MultipartFile.fromPath('file', imagePath);
      request.files.add(file);

      final streamedResponse = await request.send();
      final res = await http.Response.fromStream(streamedResponse);

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Upload failed: ${res.statusCode} ${res.body}");
    } catch (e) {
      AppLogger.e("Admin uploadProfileImage error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }

  Future<ApiResult<Map<String, dynamic>>> register({
    required String societyId,
    required String adminId,
    required String adminName,
    required String pin,
    String? phone,
    String role = "ADMIN",
  }) async {
    try {
      final body = jsonEncode({
        "society_id": societyId,
        "admin_id": adminId,
        "admin_name": adminName,
        "pin": pin,
        if (phone != null && phone.isNotEmpty) "phone": phone,
        "role": role,
      });

      AppLogger.i("Admin registration request", data: {
        "society_id": societyId,
        "admin_id": adminId,
        "role": role,
      });

      final res = await http
          .post(
            _uri("/api/admins/register"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timeout after 10 seconds");
            },
          );

      AppLogger.i("Admin registration response", data: {"status": res.statusCode, "body": res.body});

      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.failure("Registration failed: ${res.statusCode} ${res.body}");
    } on TimeoutException catch (e) {
      AppLogger.e("Admin registration timeout error", error: e);
      return ApiResult.failure("Request timeout. Please check your connection and try again.");
    } on SocketException catch (e) {
      AppLogger.e("Admin registration socket error", error: e);
      return ApiResult.failure("Cannot connect to server. Please check your network connection.");
    } catch (e) {
      AppLogger.e("Admin registration error", error: e);
      return ApiResult.failure("Connection error: ${e.toString()}");
    }
  }
}
