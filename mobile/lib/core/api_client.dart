import 'package:dio/dio.dart';

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
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      AppLogger.d('POST $path', data: {'data': data, 'query': queryParameters});
      final resp = await _dio.post(path, data: data, queryParameters: queryParameters);
      AppLogger.d('POST $path success', data: {'status': resp.statusCode});
      return resp;
    } on DioException catch (e, st) {
      final appError = AppError.fromDio(e);
      AppLogger.e('POST $path failed', error: appError.technicalMessage, stackTrace: st, data: {
        'status': e.response?.statusCode,
        'data': e.response?.data,
      });
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
