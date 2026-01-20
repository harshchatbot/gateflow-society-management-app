import 'package:gateflow/core/api_client.dart';
import 'package:gateflow/core/app_error.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/core/result.dart';
import 'package:gateflow/models/visitor.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;



class VisitorService {
  final ApiClient _client;
  VisitorService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Result<Visitor>> createVisitor({
    required String flatId,
    required String visitorType,
    required String visitorPhone,
    required String guardId,
  }) async {
    try {
      AppLogger.i('Create visitor request', data: {
        'flatId': flatId,
        'visitorType': visitorType,
        'visitorPhone': visitorPhone,
        'guardId': guardId,
      });

      final resp = await _client.post(
        '/api/visitors',
        data: {
          'flat_id': flatId,
          'visitor_type': visitorType,
          'visitor_phone': visitorPhone,
          'guard_id': guardId,
        },
      );

      final visitor = Visitor.fromJson(resp.data as Map<String, dynamic>);
      AppLogger.i('Visitor created', data: {'visitorId': visitor.visitorId, 'status': visitor.status});
      return Result.success(visitor);
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, st) {
      final err = AppError.fromUnknown(e, st);
      AppLogger.e('Create visitor unknown error', error: e, stackTrace: st);
      return Result.failure(err);
    }
  }




  Future<Result<Visitor>> createVisitorWithPhoto({
  required String flatId,
  required String visitorType,
  required String visitorPhone,
  required String guardId,
  required File photoFile,
  String? authToken,
}) async {
  try {
    final baseUrl = dotenv.env['API_BASE_URL'];
    if (baseUrl == null || baseUrl.isEmpty) {
      return Result.failure(
        AppError(
          userMessage: "API base url missing",
          technicalMessage: "API_BASE_URL not set in .env",
        ),
      );
    }

    final uri = Uri.parse("$baseUrl/api/visitors/with-photo");

    AppLogger.i('Create visitor WITH PHOTO request', data: {
      'flatId': flatId,
      'visitorType': visitorType,
      'visitorPhone': visitorPhone,
      'guardId': guardId,
      'photoPath': photoFile.path,
    });

    final request = http.MultipartRequest("POST", uri);

    if (authToken != null && authToken.isNotEmpty) {
      request.headers["Authorization"] = "Bearer $authToken";
    }

    request.fields["flat_id"] = flatId;
    request.fields["visitor_type"] = visitorType;
    request.fields["visitor_phone"] = visitorPhone;
    request.fields["guard_id"] = guardId;

    request.files.add(
      await http.MultipartFile.fromPath("photo", photoFile.path),
    );

    AppLogger.i("MULTIPART REQUEST →", data: {
      "url": uri.toString(),
      "fields": request.fields,
      "file": {
        "field": "photo",
        "path": photoFile.path,
        "size": await photoFile.length(),
      }
    });

    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);

    // 🔥 LOG FULL RESPONSE
    AppLogger.i("MULTIPART RESPONSE ←", data: {
      "status": resp.statusCode,
      "headers": resp.headers,
      "body": resp.body,
    });

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      AppLogger.e("Create visitor WITH PHOTO failed", error: {
        "status": resp.statusCode,
        "body": resp.body,
      });

      return Result.failure(
        AppError(
          userMessage: "Failed to upload photo",
          technicalMessage: "HTTP ${resp.statusCode}: ${resp.body}",
        ),
      );
    }

    final visitor = Visitor.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );

    AppLogger.i('Visitor created with photo', data: {
      'visitorId': visitor.visitorId,
      'status': visitor.status,
    });

    return Result.success(visitor);
  } on AppError catch (e) {
    return Result.failure(e);
  } catch (e, st) {
    final err = AppError.fromUnknown(e, st);
    AppLogger.e('Create visitor WITH PHOTO unknown error', error: e, stackTrace: st);
    return Result.failure(err);
  }
}


  Future<Result<List<Visitor>>> getVisitorsToday({
    required String guardId,
  }) async {
    try {
      final resp = await _client.get(
        '/api/visitors/today',
        queryParameters: {'guard_id': guardId},
      );

      final data = resp.data;
      final list = (data as List)
          .map((e) => Visitor.fromJson(e as Map<String, dynamic>))
          .toList();

      return Result.success(list);
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, st) {
      final err = AppError.fromUnknown(e, st);
      return Result.failure(err);
    }
  }

  Future<Result<List<Visitor>>> getVisitorsByFlat({
    required String flatId,
  }) async {
    try {
      final resp = await _client.get(
        '/api/visitors/by-flat',
        queryParameters: {'flat_id': flatId},
      );

      final data = resp.data;
      final list = (data as List)
          .map((e) => Visitor.fromJson(e as Map<String, dynamic>))
          .toList();

      return Result.success(list);
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, st) {
      final err = AppError.fromUnknown(e, st);
      return Result.failure(err);
    }
  }

  Future<Result<Visitor>> updateVisitorStatus({
    required String visitorId,
    required String status,
    String? approvedBy,
    String? note,
  }) async {
    try {
      final resp = await _client.post(
        '/api/visitors/$visitorId/status',
        data: {
          'status': status,
          'approved_by': approvedBy,
          'note': note,
        },
      );

      final visitor = Visitor.fromJson(resp.data as Map<String, dynamic>);
      return Result.success(visitor);
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, st) {
      final err = AppError.fromUnknown(e, st);
      return Result.failure(err);
    }
  }



}
