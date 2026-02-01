import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/resident_service.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../screens/resident_approvals_screen.dart';
import '../screens/notice_board_screen.dart';
import '../screens/resident_complaints_list_screen.dart';

/// Resident Notification Drawer
/// 
/// Shows recent notifications for residents:
/// - Pending visitor approvals
/// - Recent notices
/// - Recent complaints
class ResidentNotificationDrawer extends StatefulWidget {
  final String societyId;
  final String residentId;
  final String flatNo;

  const ResidentNotificationDrawer({
    super.key,
    required this.societyId,
    required this.residentId,
    required this.flatNo,
  });

  @override
  State<ResidentNotificationDrawer> createState() => _ResidentNotificationDrawerState();
}

class _ResidentNotificationDrawerState extends State<ResidentNotificationDrawer> {
  late final ResidentService _residentService = ResidentService(
    baseUrl: Env.apiBaseUrl,
  );
  
  late final ComplaintService _complaintService = ComplaintService(
    baseUrl: Env.apiBaseUrl,
  );
  
  late final NoticeService _noticeService = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _pendingApprovalsCount = 0;
  int _recentNoticesCount = 0;
  int _recentComplaintsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Load pending visitor approvals
      final approvalsResult = await _residentService.getApprovals(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
      );
      int pendingApprovals = 0;
      List<Map<String, dynamic>> approvalNotifications = [];

      if (approvalsResult.isSuccess && approvalsResult.data != null) {
        final allApprovals = approvalsResult.data!;
        pendingApprovals = allApprovals.length;
        
        // Get recent pending approvals (last 5)
        approvalNotifications = allApprovals
            .take(5)
            .map((a) {
              final rawVisitorName = a['visitor_name']?.toString().trim();
              final rawName = a['name']?.toString().trim();
              final rawPhone = a['visitor_phone']?.toString().trim();
              final visitorName = (rawVisitorName != null && rawVisitorName.isNotEmpty)
                  ? rawVisitorName
                  : (rawName != null && rawName.isNotEmpty)
                      ? rawName
                      : (rawPhone != null && rawPhone.isNotEmpty)
                          ? rawPhone
                          : 'Visitor';
              final visitorType = a['visitor_type']?.toString() ?? 'Guest';
              final dp = a['delivery_partner']?.toString().trim();
              final dpo = a['delivery_partner_other']?.toString().trim();
              final isDelivery = visitorType.toUpperCase() == 'DELIVERY';
              final hasDeliveryPartner = isDelivery && ((dp != null && dp.isNotEmpty) || (dpo != null && dpo.isNotEmpty));
              final deliveryLabel = hasDeliveryPartner
                  ? (dp == 'Other' ? (dpo?.isNotEmpty == true ? dpo! : 'Other') : (dp ?? ''))
                  : null;
              final description = deliveryLabel != null && deliveryLabel.isNotEmpty
                  ? '$visitorName - $visitorType ($deliveryLabel)'
                  : '$visitorName - $visitorType';
              return {
                'type': 'visitor',
                'id': a['visitor_id']?.toString() ?? '',
                'title': 'Visitor Approval Request',
                'description': description,
                'status': a['status']?.toString() ?? 'PENDING',
                'created_at': a['created_at']?.toString() ?? '',
                'visitor_name': visitorName,
                'visitor_type': visitorType,
              };
            })
            .toList();
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

      // Load recent complaints (created in last 7 days)
      final complaintsResult = await _complaintService.getResidentComplaints(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        residentId: widget.residentId,
      );
      List<Map<String, dynamic>> complaintNotifications = [];
      int recentComplaints = 0;

      if (complaintsResult.isSuccess && complaintsResult.data != null) {
        final allComplaints = complaintsResult.data!;
        final now = DateTime.now();
        
        // Get complaints from last 7 days
        final recentComplaintsList = allComplaints.where((c) {
          try {
            final createdAt = c['created_at']?.toString() ?? '';
            if (createdAt.isEmpty) return false;
            final created = DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
            final daysDiff = now.difference(created).inDays;
            return daysDiff <= 7; // Complaints from last 7 days
          } catch (e) {
            return false;
          }
        }).toList();

        recentComplaints = recentComplaintsList.length;
        complaintNotifications = recentComplaintsList
            .take(5)
            .map((c) => {
              'type': 'complaint',
              'id': c['complaint_id']?.toString() ?? '',
              'title': c['title']?.toString() ?? 'Untitled Complaint',
              'description': c['description']?.toString() ?? '',
              'status': c['status']?.toString() ?? 'PENDING',
              'created_at': c['created_at']?.toString() ?? '',
              'category': c['category']?.toString() ?? 'GENERAL',
            })
            .toList();
      }

      // Combine and sort by created_at (most recent first)
      final allNotifications = [
        ...approvalNotifications,
        ...noticeNotifications,
        ...complaintNotifications,
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
          _pendingApprovalsCount = pendingApprovals;
          _recentNoticesCount = recentNotices;
          _recentComplaintsCount = recentComplaints;
          _isLoading = false;
        });
      }

      AppLogger.i("Resident notifications loaded", data: {
        "pending_approvals": pendingApprovals,
        "recent_notices": recentNotices,
        "recent_complaints": recentComplaints,
        "total_notifications": allNotifications.length,
      });
    } catch (e, stackTrace) {
      AppLogger.e("Error loading resident notifications", error: e, stackTrace: stackTrace);
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
      case 'complaint':
        return Icons.report_problem_rounded;
      case 'visitor':
        return Icons.person_add_rounded;
      case 'notice':
        return Icons.notifications_rounded;
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
      case 'notice':
        return AppColors.success;
      default:
        return AppColors.success;
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
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_rounded, color: AppColors.success, size: 24),
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
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResidentApprovalsScreen(
                            residentId: widget.residentId,
                            societyId: widget.societyId,
                            flatNo: widget.flatNo,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSummaryCard(
                      icon: Icons.verified_rounded,
                      label: "Pending Approvals",
                      count: _pendingApprovalsCount,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoticeBoardScreen(
                            societyId: widget.societyId,
                            themeColor: AppColors.success,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSummaryCard(
                      icon: Icons.notifications_rounded,
                      label: "New Notices",
                      count: _recentNoticesCount,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResidentComplaintsListScreen(
                            residentId: widget.residentId,
                            societyId: widget.societyId,
                            flatNo: widget.flatNo,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSummaryCard(
                      icon: Icons.report_problem_rounded,
                      label: "My Complaints",
                      count: _recentComplaintsCount,
                      color: AppColors.warning,
                    ),
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
                                color: AppColors.success.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                size: 64,
                                color: AppColors.success,
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
                        color: AppColors.success,
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

  void _handleNotificationTap(Map<String, dynamic> notification) {
    final type = notification['type'] ?? '';
    
    Navigator.pop(context); // Close the drawer first
    
    if (type == 'visitor') {
      // Navigate to approvals screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResidentApprovalsScreen(
            residentId: widget.residentId,
            societyId: widget.societyId,
            flatNo: widget.flatNo,
          ),
        ),
      );
    } else if (type == 'notice') {
      // Navigate to notice board screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoticeBoardScreen(
            societyId: widget.societyId,
            themeColor: AppColors.success,
          ),
        ),
      );
    } else if (type == 'complaint') {
      // Navigate to complaints list screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResidentComplaintsListScreen(
            residentId: widget.residentId,
            societyId: widget.societyId,
            flatNo: widget.flatNo,
          ),
        ),
      );
    }
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final type = notification['type'] ?? '';
    final title = notification['title'] ?? '';
    final description = notification['description'] ?? '';
    final status = notification['status'] ?? '';
    final time = _formatTime(notification['created_at']);

    return InkWell(
      onTap: () => _handleNotificationTap(notification),
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
                    if (type == 'visitor' && notification['visitor_type'] != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.category_rounded, size: 12, color: AppColors.text2),
                      const SizedBox(width: 4),
                      Text(
                        notification['visitor_type'],
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
      ),
    );
  }
}
