import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../services/admin_service.dart';
import '../services/complaint_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';

/// Admin Notification Drawer
/// 
/// Shows recent notifications for admins:
/// - Pending complaints
/// - Recent visitor entries
/// - Recent notices
class AdminNotificationDrawer extends StatefulWidget {
  final String societyId;
  final String adminId;

  const AdminNotificationDrawer({
    super.key,
    required this.societyId,
    required this.adminId,
  });

  @override
  State<AdminNotificationDrawer> createState() => _AdminNotificationDrawerState();
}

class _AdminNotificationDrawerState extends State<AdminNotificationDrawer> {
  late final AdminService _adminService = AdminService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );
  
  late final ComplaintService _complaintService = ComplaintService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _pendingComplaintsCount = 0;
  int _recentVisitorsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
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

      // Load recent visitors (last 10)
      final visitorsResult = await _adminService.getVisitors(societyId: widget.societyId);
      List<Map<String, dynamic>> visitorNotifications = [];
      int recentVisitors = 0;

      if (visitorsResult.isSuccess && visitorsResult.data != null) {
        final allVisitors = visitorsResult.data!;
        // Get visitors from today
        final today = DateTime.now();
        final todayVisitors = allVisitors.where((v) {
          try {
            final createdAt = v['created_at']?.toString() ?? '';
            if (createdAt.isEmpty) return false;
            final created = DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
            return created.year == today.year &&
                   created.month == today.month &&
                   created.day == today.day;
          } catch (e) {
            return false;
          }
        }).toList();

        recentVisitors = todayVisitors.length;
        visitorNotifications = todayVisitors
            .take(5)
            .map((v) {
              // Handle different field name variations
              final visitorName = v['visitor_name']?.toString() ?? 
                                 v['name']?.toString() ?? 
                                 v['visitor_phone']?.toString() ?? 
                                 'Visitor';
              final flatNo = v['flat_no']?.toString() ?? 
                            v['flat_number']?.toString() ?? 
                            'N/A';
              return {
                'type': 'visitor',
                'id': v['visitor_id']?.toString() ?? '',
                'title': 'New Visitor Entry',
                'description': '$visitorName - Flat $flatNo',
                'status': v['status']?.toString() ?? 'PENDING',
                'created_at': v['created_at']?.toString() ?? '',
                'flat_no': flatNo,
                'visitor_name': visitorName,
              };
            })
            .toList();
      }

      // Combine and sort by created_at (most recent first)
      final allNotifications = [
        ...complaintNotifications,
        ...visitorNotifications,
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
          _pendingComplaintsCount = pendingComplaints;
          _recentVisitorsCount = recentVisitors;
          _isLoading = false;
        });
      }

      AppLogger.i("Admin notifications loaded", data: {
        "pending_complaints": pendingComplaints,
        "recent_visitors": recentVisitors,
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
    if (statusUpper == 'RESOLVED' || statusUpper == 'APPROVED') return AppColors.success;
    if (statusUpper == 'REJECTED') return AppColors.error;
    return AppColors.text2;
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'complaint':
        return Icons.report_problem_rounded;
      case 'visitor':
        return Icons.person_add_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getNotificationIconColor(String type) {
    switch (type) {
      case 'complaint':
        return AppColors.warning;
      case 'visitor':
        return AppColors.primary;
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

          // Summary Cards
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    icon: Icons.report_problem_rounded,
                    label: "Pending Complaints",
                    count: _pendingComplaintsCount,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    icon: Icons.person_add_rounded,
                    label: "Today's Visitors",
                    count: _recentVisitorsCount,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Notifications List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.admin),
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
                            return _buildNotificationItem(_notifications[index]);
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
