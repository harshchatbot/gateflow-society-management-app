import '../core/api_client.dart';
import '../core/app_error.dart';
import '../core/result.dart';

class SocietyRequestsService {
  final ApiClient _api = ApiClient();

  Future<Result<Map<String, dynamic>>> getDashboard() async {
    try {
      final response = await _api.get('/api/society-requests/dashboard');
      final payload = response.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      return Result.success(payload);
    } catch (e) {
      if (e is AppError) return Result.failure(e);
      return Result.failure(
        AppError(
          userMessage: 'Failed to load platform dashboard.',
          technicalMessage: e.toString(),
        ),
      );
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getPendingRequests({
    int limit = 50,
  }) async {
    try {
      final response = await _api.get(
        '/api/society-requests/pending',
        queryParameters: {'limit': limit},
      );
      final payload = response.data;
      final items = (payload is Map<String, dynamic> && payload['items'] is List)
          ? List<Map<String, dynamic>>.from(
              (payload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];
      return Result.success(items);
    } catch (e) {
      if (e is AppError) return Result.failure(e);
      return Result.failure(
        AppError(
          userMessage: 'Failed to load society requests.',
          technicalMessage: e.toString(),
        ),
      );
    }
  }

  Future<Result<Map<String, dynamic>>> approveRequest({
    required String requestId,
  }) async {
    try {
      final response = await _api.post(
        '/api/society-requests/approve',
        data: {'request_id': requestId},
      );
      final payload = response.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      return Result.success(payload);
    } catch (e) {
      if (e is AppError) return Result.failure(e);
      return Result.failure(
        AppError(
          userMessage: 'Failed to approve society request.',
          technicalMessage: e.toString(),
        ),
      );
    }
  }

  Future<Result<Map<String, dynamic>>> rejectRequest({
    required String requestId,
    String? reason,
  }) async {
    try {
      final response = await _api.post(
        '/api/society-requests/reject',
        data: {'request_id': requestId, if (reason != null) 'reason': reason},
      );
      final payload = response.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      return Result.success(payload);
    } catch (e) {
      if (e is AppError) return Result.failure(e);
      return Result.failure(
        AppError(
          userMessage: 'Failed to reject society request.',
          technicalMessage: e.toString(),
        ),
      );
    }
  }
}
