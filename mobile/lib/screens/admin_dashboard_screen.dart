import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/admin_service.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../services/notification_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import 'notice_board_screen.dart';
import 'admin_manage_notices_screen.dart';
import '../widgets/admin_notification_drawer.dart';

/// Admin Dashboard Screen
/// 
/// Overview screen for admins showing key metrics and quick actions
/// Theme: Purple/Admin theme
class AdminDashboardScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final Function(int)? onTabNavigate; // Callback to navigate to tabs

  const AdminDashboardScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    this.onTabNavigate,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminService _service = AdminService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );

  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  String? _error;
  
  late final ComplaintService _complaintService = ComplaintService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );
  
  late final NoticeService _noticeService = NoticeService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );
  
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadNotificationCount();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    // Listen for new notifications to update count
    final notificationService = NotificationService();
    notificationService.setOnNotificationReceived((data) {
      if (data['type'] == 'notice' || data['type'] == 'complaint') {
        _loadNotificationCount(); // Refresh count when notification received
      }
    });
  }

  Future<void> _loadNotificationCount() async {
    try {
      int totalCount = 0;
      
      // Count pending complaints
      final complaintsResult = await _complaintService.getAllComplaints(societyId: widget.societyId);
      if (complaintsResult.isSuccess && complaintsResult.data != null) {
        final pendingComplaints = complaintsResult.data!.where((c) {
          final status = (c['status'] ?? '').toString().toUpperCase();
          return status == 'PENDING' || status == 'IN_PROGRESS';
        }).length;
        totalCount += pendingComplaints;
      }
      
      // Count recent notices (created in last 24 hours)
      final noticesResult = await _noticeService.getNotices(
        societyId: widget.societyId,
        activeOnly: true,
      );
      if (noticesResult.isSuccess && noticesResult.data != null) {
        final now = DateTime.now();
        final recentNotices = noticesResult.data!.where((n) {
          try {
            final createdAt = n['created_at']?.toString() ?? '';
            if (createdAt.isEmpty) return false;
            final created = DateTime.parse(createdAt.replaceAll("Z", "+00:00"));
            final hoursDiff = now.difference(created).inHours;
            return hoursDiff <= 24; // Notices from last 24 hours
          } catch (e) {
            return false;
          }
        }).length;
        totalCount += recentNotices;
      }
      
      if (mounted) {
        setState(() {
          _notificationCount = totalCount;
        });
      }
    } catch (e) {
      AppLogger.e("Error loading notification count", error: e);
    }
  }

  void _showNotificationDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdminNotificationDrawer(
        societyId: widget.societyId,
        adminId: widget.adminId,
      ),
    ).then((_) {
      // Refresh notification count when drawer closes
      _loadNotificationCount();
    });
  }

  void _navigateToTab(int index) {
    if (widget.onTabNavigate != null) {
      widget.onTabNavigate!(index);
    } else {
      // Fallback: Try to find AdminShellScreen in the widget tree
      final context = this.context;
      // Navigate using a key or context - for now show message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Navigate to tab $index"),
          backgroundColor: AppColors.admin,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getStats(societyId: widget.societyId);

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _stats = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Admin dashboard stats loaded", data: _stats);
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load stats";
        });
        AppLogger.w("Failed to load admin stats: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading admin stats", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background Gradient Header (purple theme)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.admin, Color(0xFF7C3AED)], // Purple gradient
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _loadStats,
            color: AppColors.admin, // Purple refresh indicator
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),

                  // Stats Grid
                  if (_stats != null) _buildStatsGrid(),

                  const SizedBox(height: 25),
                  const Text("Quick Actions", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildActionGrid(),
                ],
              ),
            ),
          ),

          if (_isLoading) GlassLoader(show: true, message: "Loading Stats..."),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                widget.adminName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Notification Bell Icon
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded, color: Colors.white),
              onPressed: _showNotificationDrawer,
            ),
            if (_notificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    _notificationCount > 9 ? "9+" : _notificationCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.person_rounded, color: Colors.white),
          onPressed: () {
            // Navigate to profile - handled by parent shell
            // For now, show a message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Use the Profile tab below to view your account"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPremiumSocietyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.business_rounded, color: Colors.white),
          ),
          const SizedBox(width: 15),
              Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.societyId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  "Admin Portal Active",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = _stats!;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4, // Slightly adjusted to prevent overflow
      children: [
        _StatCard(
          label: "Residents",
          value: (stats['total_residents'] ?? 0).toString(),
          icon: Icons.people_rounded,
          color: AppColors.admin,
        ),
        _StatCard(
          label: "Guards",
          value: (stats['total_guards'] ?? 0).toString(),
          icon: Icons.shield_rounded,
          color: AppColors.primary,
        ),
        _StatCard(
          label: "Flats",
          value: (stats['total_flats'] ?? 0).toString(),
          icon: Icons.home_rounded,
          color: AppColors.success,
        ),
        _StatCard(
          label: "Visitors Today",
          value: (stats['visitors_today'] ?? 0).toString(),
          icon: Icons.person_add_rounded,
          color: AppColors.warning,
        ),
        _StatCard(
          label: "Pending",
          value: (stats['pending_approvals'] ?? 0).toString(),
          icon: Icons.hourglass_empty,
          color: AppColors.warning,
        ),
        _StatCard(
          label: "Approved Today",
          value: (stats['approved_today'] ?? 0).toString(),
          icon: Icons.verified_user_outlined,
          color: AppColors.success,
        ),
      ],
    );
  }

  Widget _buildActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3, // Adjusted to give more height for text
      children: [
        _ActionItem(
          icon: Icons.people_rounded,
          title: "Manage Residents",
          subtitle: "View & manage residents",
          color: AppColors.admin,
          onTap: () {
            // Navigate to Residents tab (index 1)
            _navigateToTab(1);
          },
        ),
        _ActionItem(
          icon: Icons.shield_rounded,
          title: "Manage Guards",
          subtitle: "View & manage guards",
          color: AppColors.primary,
          onTap: () {
            // Navigate to Guards tab (index 2)
            _navigateToTab(2);
          },
        ),
        _ActionItem(
          icon: Icons.home_rounded,
          title: "Manage Flats",
          subtitle: "View & manage flats",
          color: AppColors.success,
          onTap: () {
            // Navigate to Flats - show message for now (no flats screen yet)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Flats management coming soon!"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
        _ActionItem(
          icon: Icons.report_problem_rounded,
          title: "Manage Complaints",
          subtitle: "View & resolve complaints",
          color: AppColors.error,
          onTap: () {
            // Navigate to Complaints tab (index 3)
            _navigateToTab(3);
          },
        ),
        _ActionItem(
          icon: Icons.notifications_rounded,
          title: "Notice Board",
          subtitle: "View & manage notices",
          color: AppColors.warning,
          onTap: () {
            // Navigate to Notices tab (index 4)
            _navigateToTab(4);
          },
        ),
        _ActionItem(
          icon: Icons.edit_note_rounded,
          title: "Manage Notices",
          subtitle: "Create & edit notices",
          color: AppColors.admin,
          onTap: () {
            // Navigate to Notices tab (index 4) - manage notices can be accessed from there
            _navigateToTab(4);
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.text2,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text2,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
