import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';

class SosDetailScreen extends StatefulWidget {
  final String societyId;
  final String sosId;
  final String flatNo;
  final String residentName;
  final String? residentPhone;

  const SosDetailScreen({
    super.key,
    required this.societyId,
    required this.sosId,
    required this.flatNo,
    required this.residentName,
    this.residentPhone,
  });

  @override
  State<SosDetailScreen> createState() => _SosDetailScreenState();
}

class _SosDetailScreenState extends State<SosDetailScreen> {
  final FirestoreService _firestore = FirestoreService();
  DocumentSnapshot<Map<String, dynamic>>? _doc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('societies')
          .doc(widget.societyId)
          .collection('sos_requests')
          .doc(widget.sosId);
      final snap = await ref.get();
      if (mounted) {
        setState(() {
          _doc = snap;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.e("Error loading SOS detail", error: e, stackTrace: st);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateStatus(String status) async {
    try {
      await _firestore.updateSosStatus(
        societyId: widget.societyId,
        sosId: widget.sosId,
        status: status,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SOS marked $status'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      AppLogger.e("Error updating SOS status", error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update SOS status'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.residentPhone;
    final data = _doc?.data() ?? {};
    final status = (data['status'] ?? 'OPEN').toString();
    final createdAt = data['createdAt'];

    final acknowledgedByName =
        (data['acknowledgedByName'] ?? data['acknowledged_by_name'])
            ?.toString();
    final acknowledgedByRole =
        (data['acknowledgedByRole'] ?? data['acknowledged_by_role'])
            ?.toString();
    final resolvedByName =
        (data['resolvedByName'] ?? data['resolved_by_name'])?.toString();
    final resolvedByRole =
        (data['resolvedByRole'] ?? data['resolved_by_role'])?.toString();

    DateTime? created;
    if (createdAt is Timestamp) {
      created = createdAt.toDate();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Alert'),
        backgroundColor: AppColors.error,
      ),
      body: _loading
          ? AppLoader.fullscreen(show: true)
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.sos_rounded, color: AppColors.error),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Flat ${widget.flatNo}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.residentName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (phone != null && phone.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.phone_rounded, size: 18, color: AppColors.text2),
                            const SizedBox(width: 8),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      if (created != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 18, color: AppColors.text2),
                            const SizedBox(width: 8),
                            Text(
                              created.toLocal().toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.text2,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (acknowledgedByName != null &&
                          acknowledgedByName.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.person_outline_rounded,
                                size: 18, color: AppColors.text2),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                acknowledgedByRole != null
                                    ? 'Acknowledged by $acknowledgedByName (${acknowledgedByRole.toLowerCase()})'
                                    : 'Acknowledged by $acknowledgedByName',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.text2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (resolvedByName != null &&
                          resolvedByName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 18, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                resolvedByRole != null
                                    ? 'Resolved by $resolvedByName (${resolvedByRole.toLowerCase()})'
                                    : 'Resolved by $resolvedByName',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.check_circle_outline_rounded),
                              label: const Text('Mark Acknowledged'),
                              onPressed: status == 'RESOLVED' ? null : () => _updateStatus('ACKNOWLEDGED'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('Mark Resolved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: status == 'RESOLVED' ? null : () => _updateStatus('RESOLVED'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

