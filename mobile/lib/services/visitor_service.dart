import 'dart:io';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/app_error.dart';
import '../core/app_logger.dart';
import '../models/visitor.dart';

import 'package:gateflow/services/visitor_service.dart';
import 'package:gateflow/core/result.dart' as core_result;
import 'package:flutter/foundation.dart';


class Result<T> {
  final T? data;
  final AppError? error;
  bool get isSuccess => data != null && error == null;

  Result.success(this.data) : error = null;
  Result.failure(this.error) : data = null;
}

class VisitorService {
  final ApiClient _api = ApiClient();

  // ----------------------------
  // Create Visitor (JSON)
  // ----------------------------
  Future<Result<Visitor>> createVisitor({
    required String flatNo,
    String? flatId, // optional backward compatibility
    required String visitorType,
    required String visitorPhone,
    required String guardId,
  }) async {
    try {
      final payload = <String, dynamic>{
        "flat_no": flatNo.trim(),
        "flat_id": flatId,
        "visitor_type": visitorType,
        "visitor_phone": visitorPhone,
        "guard_id": guardId,
      };

      payload.removeWhere((k, v) => v == null);

      AppLogger.i("API POST /api/visitors payload=$payload");

      final res = await _api.post("/api/visitors", data: payload);

      AppLogger.i("API POST /api/visitors status=${res.statusCode} data=${res.data}");

      final visitor = Visitor.fromJson(_asMap(res.data));
      return Result.success(visitor);
    } on DioException catch (e) {
      final err = _mapDioError(e);
      AppLogger.e("createVisitor DioException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e) {
      final err = AppError(
        userMessage: "Failed to create visitor",
        technicalMessage: e.toString(),
      );
      AppLogger.e("createVisitor unknown error", error: err.technicalMessage);
      return Result.failure(err);
    }
  }

  // ----------------------------
  // Create Visitor With Photo (Multipart)
  // ----------------------------
  Future<Result<Visitor>> createVisitorWithPhoto({
    required String flatNo,
    String? flatId,
    required String visitorType,
    required String visitorPhone,
    required String guardId,
    required File photoFile,
  }) async {
    try {
      final fileName = photoFile.path.split("/").last;

      final formData = FormData.fromMap({
        "flat_no": flatNo.trim(),
        if (flatId != null) "flat_id": flatId,
        "visitor_type": visitorType,
        "visitor_phone": visitorPhone,
        "guard_id": guardId,
        "photo": await MultipartFile.fromFile(
          photoFile.path,
          filename: fileName,
        ),
      });

      AppLogger.i("API POST /api/visitors/with-photo formData(flat_no=${flatNo.trim()}, flat_id=$flatId)");

      final res = await _api.post(
        "/api/visitors/with-photo",
        data: formData,
      );

      AppLogger.i("API POST /api/visitors/with-photo status=${res.statusCode} data=${res.data}");

      final visitor = Visitor.fromJson(_asMap(res.data));
      return Result.success(visitor);
    } on DioException catch (e) {
      final err = _mapDioError(e);
      AppLogger.e("createVisitorWithPhoto DioException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e) {
      final err = AppError(
        userMessage: "Failed to create visitor with photo",
        technicalMessage: e.toString(),
      );
      AppLogger.e("createVisitorWithPhoto unknown error", error: err.technicalMessage);
      return Result.failure(err);
    }
  }

  // ----------------------------
  // Today Visitors
  // ----------------------------
  Future<Result<List<Visitor>>> getTodayVisitors({required String guardId}) async {
    final path = "/api/visitors/today/$guardId";
    try {
      AppLogger.i("API GET $path", data: {"guardId": guardId});

      final res = await _api.get(path);

      AppLogger.i("API GET $path status=${res.statusCode}", data: {
        "response_type": res.data.runtimeType.toString(),
        "has_data": res.data != null,
      });

      final data = _asMap(res.data);

      if (!data.containsKey("visitors")) {
        final err = AppError(
          userMessage: "Invalid server response (missing 'visitors')",
          technicalMessage: "Response missing visitors key: $data",
        );
        return Result.failure(err);
      }

      final raw = data["visitors"];
      if (raw is! List) {
        final err = AppError(
          userMessage: "Invalid server response (visitors is not a list)",
          technicalMessage: "visitors is ${raw.runtimeType} | data=$data",
        );
        return Result.failure(err);
      }

      late final List<Visitor> list;
      try {
        list = raw
            .map((e) => Visitor.fromJson(_asMap(e)))
            .toList();
      } catch (parseErr) {
        final err = AppError(
          userMessage: "Failed to parse visitors",
          technicalMessage: "Visitor.fromJson error: $parseErr | raw=$raw",
        );
        AppLogger.e("getTodayVisitors parse error", error: err.technicalMessage);
        return Result.failure(err);
      }

      AppLogger.i("PARSED Today visitors count=${list.length}");
      return Result.success(list);
    } on DioException catch (e) {
      final err = _mapDioError(e);
      AppLogger.e("getTodayVisitors DioException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e) {
      final err = AppError(
        userMessage: "Failed to fetch visitors",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getTodayVisitors unknown error", error: err.technicalMessage);
      return Result.failure(err);
    }
  }

  // ----------------------------
  // Visitors By Flat No (API-based)
  // ----------------------------
  Future<Result<List<Visitor>>> getVisitorsByFlatNo({
    required String guardId,
    required String flatNo,
  }) async {
    final encodedFlatNo = Uri.encodeComponent(flatNo.trim());
    final path = "/api/visitors/by-flat-no/$guardId/$encodedFlatNo";

    try {
      AppLogger.i("API GET $path (flatNo='$flatNo')");

      final res = await _api.get(path);

      AppLogger.i("API GET $path status=${res.statusCode} data=${res.data}");

      final data = _asMap(res.data);

      if (!data.containsKey("visitors")) {
        final err = AppError(
          userMessage: "Invalid server response (missing 'visitors')",
          technicalMessage: "Response missing visitors key: $data",
        );
        return Result.failure(err);
      }

      final raw = data["visitors"];
      if (raw is! List) {
        final err = AppError(
          userMessage: "Invalid server response (visitors is not a list)",
          technicalMessage: "visitors is ${raw.runtimeType} | data=$data",
        );
        return Result.failure(err);
      }

      late final List<Visitor> list;
      try {
        list = raw
            .map((e) => Visitor.fromJson(_asMap(e)))
            .toList();
      } catch (parseErr) {
        final err = AppError(
          userMessage: "Failed to parse visitors",
          technicalMessage: "Visitor.fromJson error: $parseErr | raw=$raw",
        );
        AppLogger.e("getVisitorsByFlatNo parse error", error: err.technicalMessage);
        return Result.failure(err);
      }

      AppLogger.i("PARSED ByFlat visitors count=${list.length}");
      return Result.success(list);
    } on DioException catch (e) {
      final err = _mapDioError(e);
      AppLogger.e("getVisitorsByFlatNo DioException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e) {
      final err = AppError(
        userMessage: "Failed to fetch visitors",
        technicalMessage: e.toString(),
      );
      AppLogger.e("getVisitorsByFlatNo unknown error", error: err.technicalMessage);
      return Result.failure(err);
    }
  }

  // ----------------------------
  // Backward-compatible aliases
  // ----------------------------
  Future<Result<List<Visitor>>> getVisitorsToday({required String guardId}) {
    return getTodayVisitors(guardId: guardId);
  }

  Future<Result<Visitor>> updateVisitorStatus({
    required String visitorId,
    required String status,
    String? approvedBy,
    String? note,
  }) async {
    final path = "/api/visitors/$visitorId/status";
    try {
      final payload = <String, dynamic>{
        "status": status,
        "approved_by": approvedBy,
        "note": note,
      };

      payload.removeWhere((k, v) => v == null);

      AppLogger.i("API POST $path payload=$payload");

      final res = await _api.post(
        path,
        data: payload,
      );

      AppLogger.i("API POST $path status=${res.statusCode} data=${res.data}");

      final v = Visitor.fromJson(_asMap(res.data));
      return Result.success(v);
    } on DioException catch (e) {
      final err = _mapDioError(e);
      AppLogger.e("updateVisitorStatus DioException", error: err.technicalMessage);
      return Result.failure(err);
    } catch (e) {
      final err = AppError(
        userMessage: "Failed to update status",
        technicalMessage: e.toString(),
      );
      AppLogger.e("updateVisitorStatus unknown error", error: err.technicalMessage);
      return Result.failure(err);
    }
  }



  // Add this inside your VisitorService class
  Future<Result<Map<String, dynamic>>> getGuardProfile(String guardId) async {
    final path = "/api/guards/profile/$guardId"; // Adjust this to your actual endpoint
    debugPrint("final path : $path");
    try {
      AppLogger.i("API GET $path");
      final res = await _api.get(path);
      AppLogger.i("API GET $path status=${res.statusCode} data=${res.data}");
      debugPrint("final res : ${res.data}");
      final data = _asMap(res.data);
      return Result.success(data);
    } on DioException catch (e) {
      final err = _mapDioError(e);
      return Result.failure(err);
    } catch (e) {
      debugPrint("catch e : $e");
      return Result.failure(AppError(
        userMessage: "Guard not found in system",
        technicalMessage: e.toString(),
      ));
    }
  }


  // ----------------------------
  // Helpers
  // ----------------------------

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    throw Exception("Expected Map but got ${v.runtimeType}: $v");
  }

  AppError _mapDioError(DioException e) {
    String userMessage = "Network error. Please try again.";
    String technical = e.toString();

    if (e.response != null) {
      final status = e.response?.statusCode;
      final detail = e.response?.data;

      String detailMsg = "";
      if (detail is Map && detail["detail"] != null) {
        detailMsg = detail["detail"].toString();
      } else if (detail != null) {
        detailMsg = detail.toString();
      }

      if (status == 400) userMessage = detailMsg.isNotEmpty ? detailMsg : "Invalid input";
      if (status == 401) userMessage = "Unauthorized";
      if (status == 404) userMessage = "API not found (404)";
      if (status == 500) userMessage = "Server error. Please try again.";

      technical = "HTTP $status | $detailMsg | url=${e.requestOptions.uri}";
    } else {
      technical = "DioException(no response) | ${e.type} | url=${e.requestOptions.uri} | ${e.message}";
    }

    return AppError(userMessage: userMessage, technicalMessage: technical);
  }
}
