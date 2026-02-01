import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_logger.dart';

/// Result of post-login session validation (gate check).
/// When [allowed] is true, [memberInfo] contains societyId, systemRole, and member data for routing.
/// When [allowed] is false, [blockReason] and [userMessage] describe why access was blocked.
class GateResult {
  final bool allowed;
  final GateBlockReason? blockReason;
  final String? userMessage;
  final Map<String, dynamic>? memberInfo;

  const GateResult._({
    required this.allowed,
    this.blockReason,
    this.userMessage,
    this.memberInfo,
  });

  factory GateResult.allowed(Map<String, dynamic> memberInfo) {
    return GateResult._(allowed: true, memberInfo: memberInfo);
  }

  factory GateResult.blocked(GateBlockReason reason, String userMessage) {
    return GateResult._(
      allowed: false,
      blockReason: reason,
      userMessage: userMessage,
    );
  }
}

enum GateBlockReason {
  membershipNotFound,
  memberInactive,
  societyNotFound,
  societyInactive,
}

/// Pending block message to show after navigating to Login/Join screen (e.g. RoleSelectScreen).
/// Consumed once when the target screen is built.
class GateBlockMessage {
  static String? _pending;

  static void set(String message) {
    _pending = message;
  }

  /// Returns and clears the pending message. Call from RoleSelectScreen (or similar) on first frame.
  static String? take() {
    final m = _pending;
    _pending = null;
    return m;
  }
}

/// Centralized post-login gate: validates membership and society active status.
/// Call after Firebase Auth login success (and on app startup when restoring session).
/// - Reads members/{uid} (root pointer)
/// - Reads societies/{societyId}/members/{uid} (member active)
/// - Reads societies/{societyId} (society active)
class SessionGateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _inactiveSocietyMessage =
      'This society is currently inactive. Please contact the society admin.';

  /// Validates session after login. Returns [GateResult.allowed] with member info for routing,
  /// or [GateResult.blocked] with reason and user-facing message.
  Future<GateResult> validateSessionAfterLogin(String uid) async {
    try {
      // 1) Read root pointer: members/{uid}
      final pointerDoc = await _firestore.collection('members').doc(uid).get();

      if (!pointerDoc.exists) {
        AppLogger.w('Session gate: membership not found', data: {'uid': uid});
        return GateResult.blocked(
          GateBlockReason.membershipNotFound,
          _inactiveSocietyMessage,
        );
      }

      final pointer = pointerDoc.data() as Map<String, dynamic>? ?? {};
      final societyId = pointer['societyId']?.toString()?.trim();
      if (societyId == null || societyId.isEmpty) {
        AppLogger.w('Session gate: pointer missing societyId', data: {'uid': uid});
        return GateResult.blocked(
          GateBlockReason.membershipNotFound,
          _inactiveSocietyMessage,
        );
      }

      // 2) Read society member doc: societies/{societyId}/members/{uid}
      final memberDoc = await _firestore
          .collection('societies')
          .doc(societyId)
          .collection('members')
          .doc(uid)
          .get();

      if (!memberDoc.exists) {
        AppLogger.w('Session gate: society member doc not found',
            data: {'uid': uid, 'societyId': societyId});
        return GateResult.blocked(
          GateBlockReason.membershipNotFound,
          _inactiveSocietyMessage,
        );
      }

      final memberData = memberDoc.data() as Map<String, dynamic>? ?? {};
      final memberActive = memberData['active'];
      if (memberActive == false) {
        AppLogger.i('Session gate: member inactive',
            data: {'uid': uid, 'societyId': societyId});
        return GateResult.blocked(
          GateBlockReason.memberInactive,
          _inactiveSocietyMessage,
        );
      }

      // 3) Read society doc: societies/{societyId}
      final societyDoc = await _firestore.collection('societies').doc(societyId).get();

      if (!societyDoc.exists) {
        AppLogger.w('Session gate: society not found', data: {'societyId': societyId});
        return GateResult.blocked(
          GateBlockReason.societyNotFound,
          _inactiveSocietyMessage,
        );
      }

      final societyData = societyDoc.data() as Map<String, dynamic>? ?? {};
      final societyActive = societyData['active'];
      if (societyActive == false) {
        AppLogger.i('Session gate: society inactive', data: {'societyId': societyId});
        return GateResult.blocked(
          GateBlockReason.societyInactive,
          _inactiveSocietyMessage,
        );
      }

      // Allowed: build member info for existing routing (same shape as getCurrentUserMembership)
      final memberInfo = {
        'uid': uid,
        'societyId': societyId,
        ...memberData,
      };
      AppLogger.i('Session gate: allowed', data: {'uid': uid, 'societyId': societyId});
      return GateResult.allowed(memberInfo);
    } catch (e, stackTrace) {
      AppLogger.e('Session gate: error', error: e, stackTrace: stackTrace);
      return GateResult.blocked(
        GateBlockReason.membershipNotFound,
        _inactiveSocietyMessage,
      );
    }
  }
}
