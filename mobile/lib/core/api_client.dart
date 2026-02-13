import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gateflow/core/app_error.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/core/env.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    if (Env.apiBaseUrl.isEmpty) {
      throw AppError(
        userMessage: 'API base URL not configured. Check .env file.',
        technicalMessage: 'API_BASE_URL is empty',
      );
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {
          // Default; for FormData Dio will override to multipart automatically
          'Accept': 'application/json',
        },
      ),
    );

    // ✅ Attach Firebase ID token to every request (permanent fix)
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              final token = await user.getIdToken();
              if (token != null && token.isNotEmpty) {
                options.headers['Authorization'] = 'Bearer $token';
              }
            }
          } catch (e) {
            // Non-blocking: request should still proceed even if token fetch fails
            AppLogger.w('Failed to attach Firebase token',
                data: {'err': e.toString()});
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      AppLogger.d('GET $path', data: {'query': queryParameters});
      final resp = await _dio.get(path, queryParameters: queryParameters);
      AppLogger.d('GET $path success', data: {'status': resp.statusCode});
      return resp;
    } on DioException catch (e, st) {
      final appError = AppError.fromDio(e);
      AppLogger.e(
        'GET $path failed',
        error: appError.technicalMessage,
        stackTrace: st,
        data: {
          'status': e.response?.statusCode,
          'data': e.response?.data,
        },
      );
      throw appError;
    } catch (e, st) {
      final appError = AppError(
        userMessage: 'Something went wrong. Please retry.',
        technicalMessage: e.toString(),
      );
      AppLogger.e('GET $path unexpected error', error: e, stackTrace: st);
      throw appError;
    }
  }

  Future<Response<dynamic>> post(
    String path, {
    dynamic data, // Map OR FormData
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      // Helpful log: distinguish FormData vs JSON
      AppLogger.d('POST $path', data: {
        'query': queryParameters,
        'isMultipart': data is FormData,
      });

      final resp = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
      );

      AppLogger.d('POST $path success', data: {'status': resp.statusCode});
      return resp;
    } on DioException catch (e, st) {
      final appError = AppError.fromDio(e);
      AppLogger.e(
        'POST $path failed',
        error: appError.technicalMessage,
        stackTrace: st,
        data: {
          'status': e.response?.statusCode,
          'data': e.response?.data,
        },
      );
      throw appError;
    } catch (e, st) {
      final appError = AppError(
        userMessage: 'Something went wrong. Please retry.',
        technicalMessage: e.toString(),
      );
      AppLogger.e('POST $path unexpected error', error: e, stackTrace: st);
      throw appError;
    }
  }
}
