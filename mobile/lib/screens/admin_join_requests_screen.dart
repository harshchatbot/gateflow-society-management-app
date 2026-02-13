import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../services/firestore_service.dart';
import '../services/resident_signup_service.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';

/// Admin screen: single place for all pending requests.
/// Shows:
/// (A) Admin join requests (requestedRole=admin, status=PENDING)
/// (B) Resident join requests (requestedRole=resident, status=PENDING)
/// (C) Pending resident signups (members active=false)
class AdminJoinRequestsScreen extends StatefulWidget {
  final String societyId;

  const AdminJoinRequestsScreen({super.key, required this.societyId});

  @override
  State<AdminJoinRequestsScreen> createState() =>
      _AdminJoinRequestsScreenState();
}

class _AdminJoinRequestsScreenState extends State<AdminJoinRequestsScreen> {
  final FirestoreService _firestore = FirestoreService();
  final ResidentSignupService _signupService = ResidentSignupService();

  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];

  static const String _sourceAdminJoinRequest = 'admin_join_request';
  static const String _sourceResidentJoinRequest = 'resident_join_request';
  static const String _sourcePendingSignup = 'pending_signup';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _s(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    try {
      // (A) Admin join requests
      final adminJoinList =
          await _firestore.getAdminJoinRequestsForSuperAdmin(widget.societyId);

      AppLogger.i('Admin join requests loaded',
          data: {'societyId': widget.societyId, 'count': adminJoinList.length});

      final adminJoinRequests = adminJoinList
          .map<Map<String, dynamic>>((a) {
            return {
              'source': _sourceAdminJoinRequest,
              'uid': _s(a['uid']),
              'name': _s(a['name'], fallback: 'Admin'),
              'phone': _s(a['phone']),
              // we display desired admin role in unitLabel row
              'unitLabel': _s(a['societyRole'],
                  fallback: _s(a['requestedRole'], fallback: 'ADMIN')),
              'email': _s(a['email']),
              'createdAt': a['createdAt'],
            };
          })
          .where((m) => _s(m['uid']).isNotEmpty)
          .toList();

      // (B) Resident join requests
      final residentJoinList =
          await _firestore.getResidentJoinRequestsForAdmin(widget.societyId);

      AppLogger.i('Resident join requests loaded', data: {
        'societyId': widget.societyId,
        'count': residentJoinList.length
      });

      for (final r in residentJoinList) {
        r['source'] = _sourceResidentJoinRequest;
        r['uid'] = _s(r['uid']);
        r['name'] = _s(r['name'], fallback: 'Resident');
        r['phone'] = _s(r['phone']);
        r['unitLabel'] = _s(r['unitLabel']);
      }

      // (C) Pending resident signups
      final signupsResult =
          await _signupService.getPendingSignups(societyId: widget.societyId);
      final signupList = signupsResult.data ?? [];

      AppLogger.i(
          'Found ${signupList.length} pending resident signups (from members)');

      final pendingSignups = signupList
          .map<Map<String, dynamic>>((s) {
            final uid = _s(s['uid'], fallback: _s(s['signup_id']));
            return {
              'source': _sourcePendingSignup,
              'uid': uid,
              'name': _s(s['name'], fallback: 'Resident'),
              'phone': _s(s['phone']),
              'unitLabel': _s(s['flat_no']),
              'email': _s(s['email']),
              'createdAt': s['createdAt'],
            };
          })
          .where((m) => _s(m['uid']).isNotEmpty)
          .toList();

      // Combine: admin first
      final combined = [
        ...adminJoinRequests,
        ...residentJoinList,
        ...pendingSignups
      ];

      if (!mounted) return;
      setState(() {
        _requests = combined;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('AdminJoinRequests: load failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load join requests'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _approve(Map<String, dynamic> req) async {
    final source = _s(req['source']);
    final uid = _s(req['uid']);
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid request (missing uid)'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      // Admin request approve
      if (source == _sourceAdminJoinRequest) {
        final name = _s(req['name'], fallback: 'Admin');
        final phone = _s(req['phone']);
        final desiredRole = _s(req['unitLabel'], fallback: 'ADMIN');

        await _firestore.approveAdminJoinRequest(
          societyId: widget.societyId,
          uid: uid,
          name: name,
          phoneE164: phone,
          handledByUid: adminUid,
          societyRole: desiredRole,
        );

        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin request approved'),
            backgroundColor: AppColors.success,
          ),
        );
        return;
      }

      // Pending signup approve
      if (source == _sourcePendingSignup) {
        final result = await _signupService.approveSignup(
          societyId: widget.societyId,
          signupId: uid,
          adminUid: adminUid,
        );

        await _load();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isSuccess
                ? 'Signup approved'
                : (result.error?.userMessage ?? 'Failed to approve')),
            backgroundColor:
                result.isSuccess ? AppColors.success : AppColors.error,
          ),
        );
        return;
      }

      // Resident join request approve
      final unitLabel = _s(req['unitLabel']);
      final name = _s(req['name'], fallback: 'Resident');
      final phone = _s(req['phone']);

      await _firestore.approveResidentJoinRequest(
        societyId: widget.societyId,
        uid: uid,
        unitLabel: unitLabel,
        name: name,
        phoneE164: phone,
        handledByUid: adminUid,
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request approved'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e, st) {
      AppLogger.e('AdminJoinRequests: approve failed',
          error: e, stackTrace: st);
      if (!mounted) return;

      final msg = (e is StateError) ? e.message : 'Failed to approve';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final source = _s(req['source']);
    final uid = _s(req['uid']);
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid request (missing uid)'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      // Admin request reject
      if (source == _sourceAdminJoinRequest) {
        await _firestore.rejectAdminJoinRequest(
          societyId: widget.societyId,
          uid: uid,
          handledByUid: adminUid,
        );

        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin request rejected'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // Pending signup reject
      if (source == _sourcePendingSignup) {
        final result = await _signupService.rejectSignup(
          societyId: widget.societyId,
          signupId: uid,
          adminUid: adminUid,
        );

        await _load();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isSuccess
                ? 'Signup rejected'
                : (result.error?.userMessage ?? 'Failed to reject')),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // Resident join request reject
      await _firestore.rejectResidentJoinRequest(
        societyId: widget.societyId,
        uid: uid,
        handledByUid: adminUid,
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request rejected'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e, st) {
      AppLogger.e('AdminJoinRequests: reject failed', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reject request'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _tagForSource(String source) {
    if (source == _sourceAdminJoinRequest) return 'Admin request';
    if (source == _sourceResidentJoinRequest) return 'Resident request';
    if (source == _sourcePendingSignup) return 'Society code';
    return 'Request';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Join Requests',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.text,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      body: Center(
        // ✅ HARD FIX: forces finite width for everything under body
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            child: _loading
                ? Center(child: AppLoader.inline())
                : _requests.isEmpty
                    ? const Center(
                        child: Text(
                          'No pending join requests or signups.',
                          style: TextStyle(
                            color: AppColors.text2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final r = _requests[index];
                          final source = _s(r['source']);
                          final name = _s(r['name'], fallback: 'User');
                          final phone = _s(r['phone']);
                          final unitLabel = _s(r['unitLabel']);
                          final tag = _tagForSource(source);

                          return Container(
                            width: double
                                .infinity, // ✅ finite because parent is constrained
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        tag,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (unitLabel.isNotEmpty)
                                  Text(
                                    source == _sourceAdminJoinRequest
                                        ? 'Role: $unitLabel'
                                        : 'Unit: $unitLabel',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.text2,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    phone,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.text2,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _reject(r),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _approve(r),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          minimumSize:
                                              const Size.fromHeight(44),
                                        ),
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ),
      ),
    );
  }
}
