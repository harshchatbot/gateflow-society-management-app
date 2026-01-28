import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import 'sos_detail_screen.dart';

class SosAlertsScreen extends StatefulWidget {
  final String societyId;
  final String role; // 'admin' or 'guard'

  const SosAlertsScreen({
    super.key,
    required this.societyId,
    required this.role,
  });

  @override
  State<SosAlertsScreen> createState() => _SosAlertsScreenState();
}

class _SosAlertsScreenState extends State<SosAlertsScreen> {
  final FirestoreService _firestore = FirestoreService();
  bool _loading = true;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _firestore.getSosRequests(
        societyId: widget.societyId,
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _alerts = list;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.e("Error loading SOS alerts list", error: e, stackTrace: st);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Alerts'),
        backgroundColor: AppColors.error,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _alerts.isEmpty
                ? const Center(
                    child: Text(
                      'No SOS alerts yet.',
                      style: TextStyle(color: AppColors.text2),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _alerts.length,
                    itemBuilder: (context, index) {
                      final sos = _alerts[index];
                      final sosId = (sos['sosId'] ?? '').toString();
                      final flatNo = (sos['flatNo'] ?? '').toString();
                      final residentName =
                          (sos['residentName'] ?? 'Resident').toString();
                      final phone = (sos['phone'] ?? '').toString();
                      final status = (sos['status'] ?? 'OPEN').toString();
                      final createdAt = sos['createdAt'];

                      final acknowledgedByName =
                          (sos['acknowledgedByName'] ?? sos['acknowledged_by_name'])
                              ?.toString();
                      final resolvedByName =
                          (sos['resolvedByName'] ?? sos['resolved_by_name'])
                              ?.toString();

                      DateTime? created;
                      if (createdAt is Timestamp) {
                        created = createdAt.toDate();
                      }

                      final statusUpper = status.toUpperCase();
                      Color statusColor;
                      if (statusUpper == 'OPEN') {
                        statusColor = AppColors.error;
                      } else if (statusUpper == 'ACKNOWLEDGED') {
                        statusColor = AppColors.warning;
                      } else {
                        statusColor = AppColors.success;
                      }

                      return InkWell(
                        onTap: () {
                          if (sosId.isEmpty) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SosDetailScreen(
                                societyId: widget.societyId,
                                sosId: sosId,
                                flatNo: flatNo,
                                residentName: residentName,
                                residentPhone:
                                    phone.isNotEmpty ? phone : null,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.sos_rounded,
                                  color: AppColors.error),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Flat $flatNo',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      residentName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.text2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (phone.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        phone,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                    ],
                                    if (created != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        created.toLocal().toString(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                      ],
                                    if (acknowledgedByName != null &&
                                        acknowledgedByName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Ack: $acknowledgedByName',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                    ],
                                    if (resolvedByName != null &&
                                        resolvedByName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Resolved: $resolvedByName',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.text2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: statusColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  statusUpper,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

