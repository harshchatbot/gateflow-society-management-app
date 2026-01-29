import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'admin_dashboard_screen.dart';
import 'admin_manage_residents_screen.dart';
import 'admin_manage_guards_screen.dart';
import 'admin_manage_complaints_screen.dart';
import 'admin_profile_screen.dart';
import 'notice_board_screen.dart';
import '../ui/app_colors.dart';
import '../ui/floating_bottom_nav.dart';
import '../services/notification_service.dart';

/// Admin Shell Screen
/// 
/// Main container for admin navigation with bottom nav
class AdminShellScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String role;
  final String? systemRole; // admin or super_admin

  const AdminShellScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.role,
    this.systemRole,
  });

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;
  final Map<int, bool> _screenInitialized = {};
  final GlobalKey<State<AdminDashboardScreen>> _dashboardKey = GlobalKey<State<AdminDashboardScreen>>();

  @override
  void initState() {
    super.initState();
    _screenInitialized[0] = true;
    _subscribeToNotifications();
  }

  void _onStartTourRequested() {
    setState(() => _currentIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        (_dashboardKey.currentState as dynamic)?.startTour();
      } catch (_) {}
    });
  }

  Future<void> _subscribeToNotifications() async {
    try {
      final notificationService = NotificationService();
      await notificationService.subscribeUserTopics(
        societyId: widget.societyId,
        role: "admin",
      );
    } catch (e) {
      // Notification subscription failed, continue anyway
      if (kDebugMode) {
        debugPrint("Failed to subscribe to notifications: $e");
      }
    }
  }

  /// Navigate to a specific screen index in the IndexedStack.
  /// Used by dashboard quick actions (e.g., Manage Residents, Guards, Complaints, Notices).
  void _navigateToScreen(int screenIndex) {
    setState(() {
      _currentIndex = screenIndex;
      // Mark screen as initialized when first viewed
      _screenInitialized[screenIndex] = true;
    });
  }

  /// Handle taps from the bottom navigation bar.
  /// Admin bottom nav only shows: Dashboard, Complaints, Notices, Profile.
  /// We map these tab indices to the appropriate screen indices:
  /// 0 -> Dashboard (screen 0)
  /// 1 -> Complaints (screen 3)
  /// 2 -> Notices (screen 4)
  /// 3 -> Profile (screen 5)
  void _onBottomNavTap(int tabIndex) {
    switch (tabIndex) {
      case 0:
        _navigateToScreen(0);
        break;
      case 1:
        _navigateToScreen(3);
        break;
      case 2:
        _navigateToScreen(4);
        break;
      case 3:
        _navigateToScreen(5);
        break;
      default:
        _navigateToScreen(0);
    }
  }

  Widget _buildScreen(int index) {
    // Only build screens that have been viewed at least once
    if (!_screenInitialized.containsKey(index) && index != 0) {
      // Return empty container for uninitialized screens (except dashboard)
      return Container(color: AppColors.bg);
    }

    switch (index) {
      case 0:
        return AdminDashboardScreen(
          key: _dashboardKey,
          adminId: widget.adminId,
          adminName: widget.adminName,
          societyId: widget.societyId,
          systemRole: widget.systemRole,
          onTabNavigate: _navigateToScreen,
        );
      case 1:
        return AdminManageResidentsScreen(
          adminId: widget.adminId,
          societyId: widget.societyId,
          onBackPressed: () {
            setState(() {
              _currentIndex = 0;
            });
          },
        );
      case 2:
        return AdminManageGuardsScreen(
          adminId: widget.adminId,
          societyId: widget.societyId,
          onBackPressed: () {
            setState(() {
              _currentIndex = 0;
            });
          },
        );
      case 3:
        return AdminManageComplaintsScreen(
          adminId: widget.adminId,
          societyId: widget.societyId,
          onBackPressed: () {
            setState(() {
              _currentIndex = 0;
            });
          },
        );
      case 4:
        return NoticeBoardScreen(
          societyId: widget.societyId,
          themeColor: AppColors.admin,
          adminId: widget.adminId, // Pass admin ID so manage button shows
          adminName: widget.adminName,
          useScaffold: false, // Don't use Scaffold when used as tab
          onBackPressed: () {
            setState(() {
              _currentIndex = 0; // Go back to dashboard tab
            });
          },
        );
      case 5:
        return AdminProfileScreen(
          adminId: widget.adminId,
          adminName: widget.adminName,
          societyId: widget.societyId,
          role: widget.role,
          onBackPressed: () {
            setState(() {
              _currentIndex = 0;
            });
          },
          onStartTourRequested: _onStartTourRequested,
        );
      default:
        return Container(color: AppColors.bg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(6, (index) => _buildScreen(index)),
      ),
      bottomNavigationBar: SocietyBottomNav(
        // Map current screen index back to the tab index for highlighting
        currentIndex: _currentIndex == 0
            ? 0
            : _currentIndex == 3
                ? 1
                : _currentIndex == 4
                    ? 2
                    : 3,
        onTap: _onBottomNavTap,
        showCenterButton: false, // No center button for admin
        items: const [
          FloatingNavItem(icon: Icons.dashboard_rounded, label: "Dashboard"),
          FloatingNavItem(icon: Icons.report_problem_rounded, label: "Complaints"),
          FloatingNavItem(icon: Icons.notifications_rounded, label: "Notices"),
          FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
        ],
      ),
    );
  }
}
