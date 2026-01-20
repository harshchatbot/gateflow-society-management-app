import 'package:dio/dio.dart';
import 'env.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  /// Guard login
  Future<Map<String, dynamic>> guardLogin({
    required String societyId,
    required String pin,
  }) async {
    try {
      final response = await _dio.post(
        '/api/guards/login',
        data: {
          'society_id': societyId,
          'pin': pin,
        },
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(e.response?.data['detail'] ?? 'Login failed');
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Create visitor entry
  Future<Map<String, dynamic>> createVisitor({
    required String flatId,
    required String visitorType,
    required String visitorPhone,
    required String guardId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/visitors',
        data: {
          'flat_id': flatId,
          'visitor_type': visitorType,
          'visitor_phone': visitorPhone,
          'guard_id': guardId,
        },
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(e.response?.data['detail'] ?? 'Failed to create visitor');
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}
