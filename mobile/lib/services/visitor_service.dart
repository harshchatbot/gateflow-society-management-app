import 'package:gateflow/core/api_client.dart';
import 'package:gateflow/core/app_error.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/core/result.dart';
import 'package:gateflow/models/visitor.dart';

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
}
