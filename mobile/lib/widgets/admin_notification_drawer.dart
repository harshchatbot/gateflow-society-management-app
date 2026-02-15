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
import '../core/society_modules.dart';

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
  final ValueChanged<int>? onBadgeCountChanged;

  /// Called when admin taps a pending signup item; caller should close drawer and navigate to pending signup screen.
  final VoidCallback? onNavigateToPendingSignup;
  final void Function(Map<String, dynamic> notification)? onNotificationTap;

  const AdminNotificationDrawer({
    super.key,
    required this.societyId,
    required this.adminId,
    this.onNavigateToPendingSignup,
    this.onBadgeCountChanged,
    this.onNotificationTap,
  });

  @override
  State<AdminNotificationDrawer> createState() =>
      _AdminNotificationDrawerState();
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

  /// Called by Dashboard when it wants to refresh bell badge without opening drawer.
  Future<void> refresh() async {
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // -----------------------------
      // Helpers
      // -----------------------------
      String toIso(dynamic v) {
        if (v == null) return '';
        if (v is Timestamp) return v.toDate().toIso8601String();
        if (v is DateTime) return v.toIso8601String();
        if (v is String) return v;
        return '';
      }

      // -----------------------------
      // JOIN REQUESTS (Resident + Admin)
      // -----------------------------
      int pendingSignups = 0;
      List<Map<String, dynamic>> signupNotifications = [];

      final residentJoinList =
          await _firestore.getResidentJoinRequestsForAdmin(widget.societyId);

      final adminJoinList =
          await _firestore.getAdminJoinRequestsForAdmin(widget.societyId);

      // Resident join requests
      for (final r in residentJoinList.take(5)) {
        signupNotifications.add({
          'type': 'resident_signup',
          'id': r['uid']?.toString() ?? '',
          'title': 'Join request: ${(r['name'] ?? 'Resident').toString()}',
          'description': 'Unit ${r['unitLabel'] ?? '–'}',
          'status': 'PENDING',
          'created_at': toIso(r['createdAt'] ?? r['created_at']),
          'flat_no': r['unitLabel']?.toString() ?? '',
          'resident_name': r['name']?.toString() ?? 'Resident',
        });
      }

      // Admin join requests
      for (final a in adminJoinList.take(5)) {
        signupNotifications.add({
          'type': 'admin_signup',
          'id': a['uid']?.toString() ?? '',
          'title': 'Admin access request: ${(a['name'] ?? 'Admin').toString()}',
          'description': (a['phone'] ?? '').toString().isNotEmpty
              ? 'Phone ${(a['phone'] ?? '').toString()}'
              : 'Pending admin approval',
          'status': 'PENDING',
          'created_at': toIso(a['createdAt'] ?? a['created_at']),
          'resident_name': a['name']?.toString() ?? 'Admin',
        });
      }

      pendingSignups = residentJoinList.length + adminJoinList.length;

      // -----------------------------
      // SOCIETY-CODE SIGNUPS
      // -----------------------------
      final signupsResult =
          await _signupService.getPendingSignups(societyId: widget.societyId);

      final raw = signupsResult.data;

      final List<Map<String, dynamic>> list = (raw != null)
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      pendingSignups += list.length;

      for (final s in list.take(5)) {
        signupNotifications.add({
          'type': 'resident_signup',
          'id': s['signup_id']?.toString() ?? s['uid']?.toString() ?? '',
          'title':
              'Society code signup: ${(s['name'] ?? '').toString().isNotEmpty ? s['name'] : (s['email'] ?? 'Unknown')}',
          'description': 'Flat ${s['flat_no'] ?? '–'} • ${s['email'] ?? ''}',
          'status': 'PENDING',
          'created_at': toIso(s['createdAt'] ?? s['created_at']),
          'flat_no': s['flat_no']?.toString() ?? '',
          'resident_name': s['name']?.toString() ?? 'Unknown',
        });
      }

      signupNotifications = signupNotifications.take(5).toList();

      // -----------------------------
      // COMPLAINTS
      // -----------------------------
      int pendingComplaints = 0;
      List<Map<String, dynamic>> complaintNotifications = [];

      if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
        final complaintsResult = await _complaintService.getAllComplaints(
            societyId: widget.societyId);

        if (complaintsResult.isSuccess && complaintsResult.data != null) {
          final rawComplaints = complaintsResult.data;

          final List<Map<String, dynamic>> allComplaints =
              (rawComplaints != null)
                  ? rawComplaints
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList()
                  : <Map<String, dynamic>>[];

          pendingComplaints =
              allComplaints.where(_isActionableComplaint).length;

          complaintNotifications = allComplaints
              .where(_isActionableComplaint)
              .take(5)
              .map((c) => {
                    'type': 'complaint',
                    'id': c['complaint_id']?.toString() ?? '',
                    'title': c['title']?.toString() ?? 'Untitled Complaint',
                    'description': c['description']?.toString() ?? '',
                    'status': c['status']?.toString() ?? 'PENDING',
                    'created_at': c['created_at']?.toString() ?? '',
                    'flat_no': c['flat_no']?.toString() ?? '',
                    'resident_name':
                        c['resident_name']?.toString() ?? 'Unknown',
                  })
              .toList();
        }
      }

      // -----------------------------
      // NOTICES
      // -----------------------------
      int recentNotices = 0;
      List<Map<String, dynamic>> noticeNotifications = [];

      if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
        final noticesResult = await _noticeService.getNotices(
          societyId: widget.societyId,
          activeOnly: true,
        );

        if (noticesResult.isSuccess && noticesResult.data != null) {
          final allNotices = noticesResult.data!;
          final now = DateTime.now();

          final recentNoticesList = allNotices.where((n) {
            try {
              final created =
                  DateTime.parse(n['created_at'].replaceAll("Z", "+00:00"));
              return now.difference(created).inHours <= 24;
            } catch (_) {
              return false;
            }
          }).toList();

          recentNotices = recentNoticesList.length;

          noticeNotifications = recentNoticesList.take(5).map((n) {
            final noticeType = n['notice_type']?.toString() ?? 'GENERAL';
            String typeLabel = 'Notice';
            if (noticeType == 'EMERGENCY') typeLabel = 'Alert';
            if (noticeType == 'SCHEDULE') typeLabel = 'Event';
            if (noticeType == 'MAINTENANCE') typeLabel = 'Maintenance';

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
          }).toList();
        }
      }

      // -----------------------------
      // SOS
      // -----------------------------
      int openSos = 0;
      List<Map<String, dynamic>> sosNotifications = [];

      if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
        final sosList =
            await _firestore.getSosRequests(societyId: widget.societyId);

        final openOnly = sosList.where((s) {
          final status = (s['status'] ?? 'OPEN').toString().toUpperCase();
          return status == 'OPEN';
        }).toList();

        openSos = openOnly.length;

        sosNotifications = openOnly.take(5).map((s) {
          return {
            'type': 'sos',
            'id': (s['sosId'] ?? '').toString(),
            'title': 'SOS from Flat ${(s['flatNo'] ?? '').toString()}',
            'description': (s['residentName'] ?? 'Resident').toString(),
            'status': s['status']?.toString() ?? 'OPEN',
            'created_at': toIso(s['createdAt']),
            'flat_no': (s['flatNo'] ?? '').toString(),
            'resident_name': (s['residentName'] ?? 'Resident').toString(),
          };
        }).toList();
      }

      // ✅ total badge count computed ONLY here
      final totalBadgeCount =
          pendingSignups + pendingComplaints + recentNotices + openSos;

      // -----------------------------
      // COMBINE + SORT
      // -----------------------------
      final allNotifications = [
        ...signupNotifications,
        ...sosNotifications,
        ...complaintNotifications,
        ...noticeNotifications,
      ];

      allNotifications.sort((a, b) {
        try {
          return DateTime.parse(b['created_at'])
              .compareTo(DateTime.parse(a['created_at']));
        } catch (_) {
          return 0;
        }
      });

      // -----------------------------
      // UPDATE UI
      // -----------------------------
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

      // ✅ Push badge count up to the dashboard bell
      widget.onBadgeCountChanged?.call(totalBadgeCount);

      AppLogger.i("Admin notifications loaded", data: {
        "pending_resident_join": residentJoinList.length,
        "pending_admin_join": adminJoinList.length,
        "pending_signups_total": pendingSignups,
        "pending_complaints": pendingComplaints,
        "recent_notices": recentNotices,
        "open_sos": openSos,
        "badge_total": totalBadgeCount,
        "total_notifications": allNotifications.length,
      });
    } catch (e, st) {
      AppLogger.e("Error loading admin notifications",
          error: e, stackTrace: st);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isActionableComplaint(Map<String, dynamic> complaint) {
    final status = (complaint['status'] ?? '').toString().toUpperCase().trim();
    if (!(status == 'PENDING' || status == 'IN_PROGRESS')) return false;
    final resolvedAt = complaint['resolvedAt'] ?? complaint['resolved_at'];
    return resolvedAt == null;
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
    if (statusUpper == 'RESOLVED' ||
        statusUpper == 'APPROVED' ||
        statusUpper == 'ACTIVE') {
      return AppColors.success;
    }
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.notifications_rounded,
                      color: cs.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Recent updates & pending items",
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: cs.onSurface.withValues(alpha: 0.65)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Summary Cards (horizontal scroll, filtered by enabled modules)
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
                    label: "Pending Residents",
                    count: _pendingSignupsCount,
                    color: AppColors.success,
                  ),
                ),
                if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) ...[
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
                ],
                if (SocietyModules.isEnabled(SocietyModuleIds.notices)) ...[
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
                ],
                if (SocietyModules.isEnabled(SocietyModuleIds.sos)) ...[
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
                                color: AppColors.admin.withValues(alpha: 0.1),
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
                                color: AppColors.text2.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        color: cs.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            final notification = _notifications[index];
                            return _buildNotificationItem(notification);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: cs.onPrimary,
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
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = notification['type'] ?? '';
    final title = notification['title'] ?? '';
    final description = notification['description'] ?? '';
    final status = notification['status'] ?? '';
    final time = _formatTime(notification['created_at']);

    return GestureDetector(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: cs.onSurface.withValues(alpha: 0.04),
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
                color: _getNotificationIconColor(type).withValues(alpha: 0.15),
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
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(status).withValues(alpha: 0.15),
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
                      color: cs.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (type == 'complaint' &&
                          notification['flat_no'] != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.home_rounded,
                            size: 12,
                            color: cs.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Text(
                          "Flat ${notification['flat_no']}",
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (type == 'notice' &&
                          notification['type_label'] != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.category_rounded,
                            size: 12,
                            color: cs.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Text(
                          notification['type_label'],
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.6),
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
      ),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    // 🔍 Log to confirm tap works
    AppLogger.i("Notification tapped (drawer)", data: {
      "type": notification['type'],
      "id": notification['id'],
    });

    // ✅ Drawer does NOT navigate
    // It only informs the parent (AdminDashboard)
    if (widget.onNotificationTap != null) {
      widget.onNotificationTap!(notification);
    }
  }
}
