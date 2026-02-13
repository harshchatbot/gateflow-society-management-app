import 'dart:io';

import 'package:dio/dio.dart';

/// Domain-level error with user-friendly messaging.
class AppError implements Exception {
  final String userMessage;
  final String technicalMessage;

  AppError({required this.userMessage, required this.technicalMessage});

  @override
  String toString() => userMessage;

  static AppError fromDio(DioException e) {
    // Network / connectivity
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AppError(
        userMessage:
            'Server took too long to respond. Check network and retry.',
        technicalMessage: 'Timeout: ${e.message}',
      );
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown && e.error is SocketException) {
      return AppError(
        userMessage: 'Server not reachable. Check Wi‑Fi or mobile data.',
        technicalMessage: 'Socket/connection error: ${e.error}',
      );
    }

    // Backend responded with error payload
    final status = e.response?.statusCode;
    final detail = e.response?.data is Map<String, dynamic>
        ? (e.response?.data['detail']?.toString() ?? '')
        : e.response?.data?.toString() ?? '';

    if (status != null && status >= 400 && status < 500) {
      return AppError(
        userMessage: detail.isNotEmpty
            ? detail
            : 'Request was rejected. Please verify the details.',
        technicalMessage: 'HTTP $status: $detail',
      );
    }

    if (status != null && status >= 500) {
      return AppError(
        userMessage: 'Server error. Please try again shortly.',
        technicalMessage: 'HTTP $status: $detail',
      );
    }

    // Fallback
    return AppError(
      userMessage: 'Something went wrong. Please retry.',
      technicalMessage: e.message ?? 'Unknown Dio error',
    );
  }

  static AppError fromUnknown(Object error, StackTrace? stackTrace) {
    return AppError(
      userMessage: 'Unexpected error. Please retry.',
      technicalMessage: '$error\n$stackTrace',
    );
  }
}
