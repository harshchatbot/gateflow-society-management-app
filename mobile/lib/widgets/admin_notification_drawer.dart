import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../services/resident_signup_service.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';

/// Admin Notification Drawer
///
/// Shows recent notifications for admins:
/// - Pending resident signups
/// - Pending complaints
/// - Recent notices
/// - Open SOS
class AdminNotificationDrawer extends StatefulWidget {
  final String societyId;
  final String adminId;
  /// Called when admin taps a pending signup item; caller should close drawer and navigate to pending signup screen.
  final VoidCallback? onNavigateToPendingSignup;

  const AdminNotificationDrawer({
    super.key,
    required this.societyId,
    required this.adminId,
    this.onNavigateToPendingSignup,
  });

  @override
  State<AdminNotificationDrawer> createState() => _AdminNotificationDrawerState();
}

class _AdminNotificationDrawerState extends State<AdminNotificationDrawer> {
  late final ComplaintService _complaintService = ComplaintService(
    baseUrl: Env.apiBaseUrl,
  );
  
  late final NoticeService _noticeService = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );

  final ResidentSignupService _signupService = ResidentSignupService();
  final FirestoreService _firestore = FirestoreService();

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _pendingSignupsCount = 0;
  int _pendingComplaintsCount = 0;
  int _recentNoticesCount = 0;
  int _openSosCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Load pending resident signups
      int pendingSignups = 0;
      List<Map<String, dynamic>> signupNotifications = [];
      final signupsResult = await _signupService.getPendingSignups(societyId: widget.societyId);
      if (signupsResult.isSuccess && signupsResult.data != null) {
        final list = signupsResult.data!;
        pendingSignups = list.length;
        signupNotifications = list.take(5).map((s) {
          return {
            'type': 'resident_signup',
            'id': s['signup_id']?.toString() ?? s['uid']?.toString() ?? '',
            'title': 'Resident signup: ${(s['name'] ?? '').toString().isNotEmpty ? s['name'] : (s['email'] ?? 'Unknown')}',
            'description': 'Flat ${s['flat_no'] ?? '–'} • ${s['email'] ?? ''}',
            'status': 'PENDING',
            'created_at': s['created_at']?.toString() ?? '',
            'flat_no': s['flat_no']?.toString() ?? '',
            'resident_name': s['name']?.toString() ?? 'Unknown',
          };
        }).toList();
      }

      // Load pending complaints
      final complaintsResult = await _complaintService.getAllComplaints(societyId: widget.societyId);
      int pendingComplaints = 0;
      List<Map<String, dynamic>> complaintNotifications = [];

      if (complaintsResult.isSuccess && complaintsResult.data != null) {
        final allComplaints = complaintsResult.data!;
        pendingComplaints = allComplaints.where((c) {
          final status = (c['status'] ?? '').toString().toUpperCase();
          return status == 'PENDING' || status == 'IN_PROGRESS';
        }).length;

        // Get recent pending complaints (last 5)
        final recentPending = allComplaints
            .where((c) {
              final status = (c['status'] ?? '').toString().toUpperCase();
              return status == 'PENDING' || status == 'IN_PROGRESS';
            })
            .take(5)
            .map((c) => {
              'type': 'complaint',
              'id': c['complaint_id']?.toString() ?? '',
              'title': c['title']?.toString() ?? 'Untitled Complaint',
              'description': c['description']?.toString() ?? '',
              'status': c['status']?.toString() ?? 'PENDING',
              'created_at': c['created_at']?.toString() ?? '',
              'flat_no': c['flat_no']?.toString() ?? '',
              'resident_name': c['resident_name']?.toString() ?? 'Unknown',
            })
            .toList();
        
        complaintNotifications = recentPending;
      }

      // Load recent notices (created in last 24 hours)
      final noticesResult = await _noticeService.getNotices(
        societyId: widget.societyId,
        activeOnly: true,
      );
      List<Map<String, dynamic>> noticeNotifications = [];
      int recentNotices = 0;

      if (noticesResult.isSuccess && noticesResult.data != null) {
        final allNotices = noticesResult.data!;
        final now = DateTime.now();
        
        // Get notices from last 24 hours
        final recentNoticesList = allNotices.where((n) {
          try {
            final createdAt = n['created_at']?.toString() ?? '';
            if (createdAt.isEmpty) return false;
            final created = DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
            final hoursDiff = now.difference(created).inHours;
            return hoursDiff <= 24; // Notices from last 24 hours
          } catch (e) {
            return false;
          }
        }).toList();

        recentNotices = recentNoticesList.length;
        noticeNotifications = recentNoticesList
            .take(5)
            .map((n) {
              final noticeType = n['notice_type']?.toString() ?? 'GENERAL';
              String typeLabel = 'Notice';
              if (noticeType == 'EMERGENCY') typeLabel = 'Alert';
              else if (noticeType == 'SCHEDULE') typeLabel = 'Event';
              else if (noticeType == 'MAINTENANCE') typeLabel = 'Maintenance';
              else if (noticeType == 'GENERAL') typeLabel = 'Announcement';
              
              return {
                'type': 'notice',
                'id': n['notice_id']?.toString() ?? '',
                'title': n['title']?.toString() ?? 'Untitled Notice',
                'description': n['content']?.toString() ?? '',
                'status': n['status']?.toString() ?? 'ACTIVE',
                'created_at': n['created_at']?.toString() ?? '',
                'notice_type': noticeType,
                'type_label': typeLabel,
                'priority': n['priority']?.toString() ?? 'NORMAL',
              };
            })
            .toList();
      }

      // Load open SOS alerts from Firestore for this society (treated as actionable notifications)
      List<Map<String, dynamic>> sosNotifications = [];
      int openSos = 0;
      try {
        final sosList = await _firestore.getSosRequests(
          societyId: widget.societyId,
          limit: 50,
        );

        final openOnly = sosList.where((s) {
          final status = (s['status'] ?? 'OPEN').toString().toUpperCase();
          return status == 'OPEN';
        }).toList();

        openSos = openOnly.length;

        sosNotifications = openOnly.map((s) {
          final flatNo = (s['flatNo'] ?? '').toString();
          final residentName = (s['residentName'] ?? 'Resident').toString();
          final createdAt = s['createdAt'];
          String? createdAtIso;
          if (createdAt is Timestamp) {
            createdAtIso = createdAt.toDate().toIso8601String();
          } else if (createdAt is DateTime) {
            createdAtIso = createdAt.toIso8601String();
          }

          return {
            'type': 'sos',
            'id': (s['sosId'] ?? '').toString(),
            'title': 'SOS from Flat $flatNo',
            'description': residentName,
            'status': (s['status'] ?? 'OPEN').toString(),
            'created_at': createdAtIso ?? '',
            'flat_no': flatNo,
            'resident_name': residentName,
          };
        }).toList();
      } catch (e, st) {
        AppLogger.e("Error loading SOS notifications (admin drawer)", error: e, stackTrace: st);
      }

      // Combine and sort by created_at (most recent first)
      final allNotifications = [
        ...signupNotifications,
        ...sosNotifications,
        ...complaintNotifications,
        ...noticeNotifications,
      ];

      allNotifications.sort((a, b) {
        try {
          final aTime = DateTime.parse(a['created_at']?.toString().replaceAll("Z", "+00:00") ?? '');
          final bTime = DateTime.parse(b['created_at']?.toString().replaceAll("Z", "+00:00") ?? '');
          return bTime.compareTo(aTime); // Most recent first
        } catch (e) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _notifications = allNotifications;
          _pendingSignupsCount = pendingSignups;
          _pendingComplaintsCount = pendingComplaints;
          _recentNoticesCount = recentNotices;
          _openSosCount = openSos;
          _isLoading = false;
        });
      }

      AppLogger.i("Admin notifications loaded", data: {
        "pending_signups": pendingSignups,
        "pending_complaints": pendingComplaints,
        "recent_notices": recentNotices,
        "open_sos": openSos,
        "total_notifications": allNotifications.length,
      });
    } catch (e, stackTrace) {
      AppLogger.e("Error loading admin notifications", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return "Just now";
    try {
      final dateTime = DateTime.parse(dateTimeStr.replaceAll("Z", "+00:00"));
      final now = DateTime.now().toUtc();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) return "Just now";
      if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
      if (difference.inHours < 24) return "${difference.inHours}h ago";
      if (difference.inDays < 7) return "${difference.inDays}d ago";
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    } catch (e) {
      return "Recently";
    }
  }

  Color _getStatusColor(String status) {
    final statusUpper = status.toUpperCase();
    if (statusUpper == 'PENDING') return AppColors.warning;
    if (statusUpper == 'IN_PROGRESS') return AppColors.primary;
    if (statusUpper == 'RESOLVED' || statusUpper == 'APPROVED' || statusUpper == 'ACTIVE') return AppColors.success;
    if (statusUpper == 'REJECTED') return AppColors.error;
    return AppColors.text2;
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'resident_signup':
        return Icons.person_add_rounded;
      case 'complaint':
        return Icons.report_problem_rounded;
      case 'visitor':
        return Icons.person_add_rounded;
      case 'notice':
        return Icons.notifications_rounded;
      case 'sos':
        return Icons.sos_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getNotificationIconColor(String type) {
    switch (type) {
      case 'resident_signup':
        return AppColors.success;
      case 'sos':
        return AppColors.error;
      case 'complaint':
        return AppColors.warning;
      case 'visitor':
        return AppColors.primary;
      case 'notice':
        return AppColors.admin;
      default:
        return AppColors.admin;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.admin.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_rounded, color: AppColors.admin, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Recent updates & pending items",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Summary Cards (horizontal scroll to avoid overflow on narrow screens)
          SizedBox(
            height: 100,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(
                  width: 120,
                  child: _buildSummaryCard(
                    icon: Icons.person_add_rounded,
                    label: "Pending Signups",
                    count: _pendingSignupsCount,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: _buildSummaryCard(
                    icon: Icons.report_problem_rounded,
                    label: "Pending Complaints",
                    count: _pendingComplaintsCount,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: _buildSummaryCard(
                    icon: Icons.notifications_rounded,
                    label: "New Notices",
                    count: _recentNoticesCount,
                    color: AppColors.admin,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: _buildSummaryCard(
                    icon: Icons.sos_rounded,
                    label: "Open SOS",
                    count: _openSosCount,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),

          // Notifications List
          Expanded(
            child: _isLoading
                ? Center(
                    child: AppLoader.inline(size: 28),
                  )
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.admin.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                size: 64,
                                color: AppColors.admin,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "No notifications",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "You're all caught up!",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.text2.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        color: AppColors.admin,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            final notification = _notifications[index];
                            final type = notification['type'] ?? '';
                            final isSignup = type == 'resident_signup';
                            return InkWell(
                              onTap: isSignup && widget.onNavigateToPendingSignup != null
                                  ? () {
                                      widget.onNavigateToPendingSignup!();
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              child: _buildNotificationItem(notification),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final type = notification['type'] ?? '';
    final title = notification['title'] ?? '';
    final description = notification['description'] ?? '';
    final status = notification['status'] ?? '';
    final time = _formatTime(notification['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _getNotificationIconColor(type).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getNotificationIcon(type),
              color: _getNotificationIconColor(type),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _getStatusColor(status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 12, color: AppColors.text2),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.text2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (type == 'complaint' && notification['flat_no'] != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.home_rounded, size: 12, color: AppColors.text2),
                      const SizedBox(width: 4),
                      Text(
                        "Flat ${notification['flat_no']}",
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (type == 'notice' && notification['type_label'] != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.category_rounded, size: 12, color: AppColors.text2),
                      const SizedBox(width: 4),
                      Text(
                        notification['type_label'],
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
