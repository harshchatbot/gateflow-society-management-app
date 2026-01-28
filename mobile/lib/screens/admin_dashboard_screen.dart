import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/admin_service.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import 'notice_board_screen.dart';
import 'sos_detail_screen.dart';
import 'sos_alerts_screen.dart';
import 'admin_manage_notices_screen.dart';
import 'admin_manage_admins_screen.dart';
import 'role_select_screen.dart';
import '../widgets/admin_notification_drawer.dart';

/// Admin Dashboard Screen
/// 
/// Overview screen for admins showing key metrics and quick actions
/// Theme: Purple/Admin theme
class AdminDashboardScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String? systemRole; // admin or super_admin
  final Function(int)? onTabNavigate; // Callback to navigate to tabs

  const AdminDashboardScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    this.systemRole,
    this.onTabNavigate,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminService _service = AdminService(
    baseUrl: Env.apiBaseUrl,
  );

  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  String? _error;
  
  late final ComplaintService _complaintService = ComplaintService(
    baseUrl: Env.apiBaseUrl,
  );
  
  late final NoticeService _noticeService = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );
  
  int _notificationCount = 0;
  int _sosBadgeCount = 0;
  final FirestoreService _firestore = FirestoreService();
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadNotificationCount();
    _setupNotificationListener();
    _loadAdminProfile();
  }

  Future<void> _loadAdminProfile() async {
    try {
      final membership = await _firestore.getCurrentUserMembership();
      if (!mounted || membership == null) return;

      setState(() {
        _photoUrl = membership['photoUrl'] as String?;
      });
    } catch (e, st) {
      AppLogger.e("Error loading admin profile photo", error: e, stackTrace: st);
    }
  }

  void _setupNotificationListener() {
    // Listen for new notifications to update count
    final notificationService = NotificationService();
    notificationService.setOnNotificationReceived((data) {
      if (data['type'] == 'notice' || data['type'] == 'complaint') {
        _loadNotificationCount(); // Refresh count when notification received
      } else if (data['type'] == 'sos') {
        // Increment SOS badge while app is running
        if (mounted) {
          setState(() {
            _sosBadgeCount += 1;
          });
        }
      }
    });
    notificationService.setOnNotificationTap((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'complaint') {
        // Navigate to complaints tab (index 3)
        _navigateToTab(3);
      } else if (type == 'notice') {
        // Navigate to notices tab (index 4)
        _navigateToTab(4);
      } else if (type == 'sos') {
        final societyId = (data['society_id'] ?? widget.societyId).toString();
        final flatNo = (data['flat_no'] ?? '').toString();
        final residentName = (data['resident_name'] ?? 'Resident').toString();
        final phone = (data['resident_phone'] ?? '').toString();
        final sosId = (data['sos_id'] ?? '').toString();

        if (!mounted || sosId.isEmpty) return;

        // Increment SOS badge so bell reflects SOS attention
        setState(() {
          _sosBadgeCount += 1;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SosDetailScreen(
              societyId: societyId,
              sosId: sosId,
              flatNo: flatNo,
              residentName: residentName,
              residentPhone: phone.isNotEmpty ? phone : null,
            ),
          ),
        );
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

  Future<void> _onWillPop() async {
    // Show confirmation dialog when back is pressed on dashboard
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text('Do you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (shouldExit == true && context.mounted) {
      // Navigate to role select instead of just popping
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: Scaffold(
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
            onRefresh: () async {
              await _loadStats();
              await _loadAdminProfile();
            },
            color: AppColors.admin, // Purple refresh indicator
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),

                  // Top category strip (Residents / Guards / Complaints / Notices)
                  const Text(
                    "Explore",
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTopCategoryStrip(),

                  const SizedBox(height: 24),
                  if (_stats != null) ...[
                    const Text(
                      "Today at a glance",
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatsSection(),
                  ],

                  const SizedBox(height: 25),
                  const Text(
                    "Your actions",
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildActionGrid(),
                  const SizedBox(height: 25),
                ],
              ),
            ),
          ),

          if (_isLoading) GlassLoader(show: true, message: "Loading Stats..."),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        // Small profile avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 2,
            ),
          ),
          child: CircleAvatar(
            backgroundColor: Colors.white24,
            backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                ? NetworkImage(_photoUrl!)
                : null,
            child: (_photoUrl == null || _photoUrl!.isEmpty)
                ? const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
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
            Builder(
              builder: (context) {
                final totalBadgeCount = _notificationCount + _sosBadgeCount;
                if (totalBadgeCount <= 0) return const SizedBox.shrink();
                return Positioned(
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
                      totalBadgeCount > 9 ? "9+" : totalBadgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ],
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

  /// Horizontal strip of rounded category chips for key admin areas
  Widget _buildTopCategoryStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildCategoryChip(
            icon: Icons.people_rounded,
            label: "Residents",
            color: AppColors.admin,
            onTap: () => _navigateToTab(1),
          ),
          const SizedBox(width: 8),
          _buildCategoryChip(
            icon: Icons.shield_rounded,
            label: "Guards",
            color: AppColors.primary,
            onTap: () => _navigateToTab(2),
          ),
          const SizedBox(width: 8),
          _buildCategoryChip(
            icon: Icons.report_problem_rounded,
            label: "Complaints",
            color: AppColors.error,
            onTap: () => _navigateToTab(3),
          ),
          const SizedBox(width: 8),
          _buildCategoryChip(
            icon: Icons.notifications_rounded,
            label: "Notices",
            color: AppColors.warning,
            onTap: () => _navigateToTab(4),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps the existing stats grid into a soft card module
  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: _buildStatsGrid(),
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
          icon: Icons.sos_rounded,
          title: "SOS Alerts",
          subtitle: "View emergency SOS history",
          color: AppColors.error,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SosAlertsScreen(
                  societyId: widget.societyId,
                  role: 'admin',
                ),
              ),
            );
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
        // Only show "Manage Admins" for super admins
        if (widget.systemRole?.toLowerCase() == 'super_admin')
          _ActionItem(
            icon: Icons.admin_panel_settings_rounded,
            title: "Manage Admins",
            subtitle: "Approve admin signups",
            color: AppColors.admin,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminManageAdminsScreen(
                    adminId: widget.adminId,
                    societyId: widget.societyId,
                    systemRole: widget.systemRole,
                  ),
                ),
              );
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
