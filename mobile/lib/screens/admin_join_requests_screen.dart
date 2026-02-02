import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';

/// Admin screen: review and approve/reject resident join requests
/// from public_societies/{societyId}/join_requests.
class AdminJoinRequestsScreen extends StatefulWidget {
  final String societyId;

  const AdminJoinRequestsScreen({super.key, required this.societyId});

  @override
  State<AdminJoinRequestsScreen> createState() =>
      _AdminJoinRequestsScreenState();
}

class _AdminJoinRequestsScreenState extends State<AdminJoinRequestsScreen> {
  final FirestoreService _firestore = FirestoreService();
  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list =
          await _firestore.getResidentJoinRequestsForAdmin(widget.societyId);
      if (!mounted) return;
      setState(() {
        _requests = list;
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
    final uid = req['uid'] as String;
    final unitLabel = (req['unitLabel'] as String?) ?? '';
    final name = (req['name'] as String?) ?? 'Resident';
    final phone = (req['phone'] as String?) ?? '';
    final handledByUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

    try {
      await _firestore.approveResidentJoinRequest(
        societyId: widget.societyId,
        uid: uid,
        unitLabel: unitLabel,
        name: name,
        phoneE164: phone,
        handledByUid: handledByUid,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message ?? 'Failed to approve request'
                : 'Failed to approve request',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final uid = req['uid'] as String;
    final handledByUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    try {
      await _firestore.rejectResidentJoinRequest(
        societyId: widget.societyId,
        uid: uid,
        handledByUid: handledByUid,
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
      AppLogger.e('AdminJoinRequests: reject failed',
          error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reject request'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
      body: _loading
          ? Center(child: AppLoader.inline())
          : _requests.isEmpty
              ? Center(
                  child: Text(
                    'No pending join requests.',
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
                    final name = (r['name'] as String?) ?? 'Resident';
                    final phone = (r['phone'] as String?) ?? '';
                    final unitLabel = (r['unitLabel'] as String?) ?? '';
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Unit: $unitLabel',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.text2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              phone,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.text2,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _reject(r),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                ),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _approve(r),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Approve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

