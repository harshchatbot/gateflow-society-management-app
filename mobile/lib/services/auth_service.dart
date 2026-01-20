import 'package:gateflow/core/api_client.dart';
import 'package:gateflow/core/app_error.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/core/result.dart';
import 'package:gateflow/models/guard.dart';

class AuthService {
  final ApiClient _client;
  AuthService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Result<Guard>> login({
    required String societyId,
    required String pin,
  }) async {
    try {
      AppLogger.i('Login request', data: {'societyId': societyId});
      final resp = await _client.post(
        '/api/guards/login',
        data: {
          'society_id': societyId,
          'pin': pin,
        },
      );
      final guard = Guard.fromJson(resp.data as Map<String, dynamic>);
      AppLogger.i('Login success', data: {'guardId': guard.guardId});
      return Result.success(guard);
    } on AppError catch (e) {
      return Result.failure(e);
    } catch (e, st) {
      final err = AppError.fromUnknown(e, st);
      AppLogger.e('Login unknown error', error: e, stackTrace: st);
      return Result.failure(err);
    }
  }
}
