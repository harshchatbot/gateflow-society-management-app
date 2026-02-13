import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'admin_dashboard_screen.dart';
import 'admin_manage_residents_screen.dart';
import 'admin_manage_guards_screen.dart';
import 'admin_manage_complaints_screen.dart';
import 'admin_profile_screen.dart';
import 'notice_board_screen.dart';
import '../ui/floating_bottom_nav.dart';
import '../services/notification_service.dart';
import '../core/society_modules.dart';

/// Admin Shell Screen
///
/// Main container for admin navigation with bottom nav
class AdminShellScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String role;
  final String systemRole; // admin or super_admin

  const AdminShellScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.role,
    required this.systemRole,
  });

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;
  final Map<int, bool> _screenInitialized = {};
  final GlobalKey<State<AdminDashboardScreen>> _dashboardKey =
      GlobalKey<State<AdminDashboardScreen>>();
  bool _modulesReady = false;

  @override
  void initState() {
    super.initState();
    _screenInitialized[0] = true;
    _subscribeToNotifications();
    SocietyModules.refresh(widget.societyId).then((_) {
      if (mounted) setState(() => _modulesReady = true);
    });
  }

  void _onStartTourRequested() {
    setState(() => _currentIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        try {
          (_dashboardKey.currentState as dynamic)?.startTour();
        } catch (_) {}
      });
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
  void _navigateToScreen(int screenIndex, {int? residentsSubTab}) {
    setState(() {
      _currentIndex = screenIndex;
      _screenInitialized[screenIndex] = true;
    });
  }

  /// Build nav items and tab->screen mapping from enabled modules.
  List<FloatingNavItem> _buildNavItems() {
    final items = <FloatingNavItem>[
      const FloatingNavItem(icon: Icons.dashboard_rounded, label: "Dashboard"),
    ];
    if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
      items.add(const FloatingNavItem(
          icon: Icons.report_problem_rounded, label: "Complaints"));
    }
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      items.add(const FloatingNavItem(
          icon: Icons.notifications_rounded, label: "Notices"));
    }
    items.add(
        const FloatingNavItem(icon: Icons.person_rounded, label: "Profile"));
    return items;
  }

  List<int> _buildTabToScreenIndex() {
    final list = <int>[0]; // Dashboard
    if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) list.add(3);
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) list.add(4);
    list.add(5); // Profile
    return list;
  }

  int _getCurrentTabIndex() {
    final tabToScreen = _buildTabToScreenIndex();
    for (var i = 0; i < tabToScreen.length; i++) {
      if (tabToScreen[i] == _currentIndex) return i;
    }
    return 0;
  }

  /// Handle taps from the bottom navigation bar.
  void _onBottomNavTap(int tabIndex) {
    if (!_modulesReady) {
      if (tabIndex == 0) {
        _navigateToScreen(0);
      } else if (tabIndex == 1) {
        _navigateToScreen(5);
      }
      return;
    }
    final tabToScreen = _buildTabToScreenIndex();
    if (tabIndex >= 0 && tabIndex < tabToScreen.length) {
      _navigateToScreen(tabToScreen[tabIndex]);
    } else {
      _navigateToScreen(0);
    }
  }

  Widget _buildScreen(int index) {
    // Only build screens that have been viewed at least once
    if (!_screenInitialized.containsKey(index) && index != 0) {
      // Return empty container for uninitialized screens (except dashboard)
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    switch (index) {
      case 0:
        return AdminDashboardScreen(
          key: _dashboardKey,
          adminId: widget.adminId,
          adminName: widget.adminName,
          societyId: widget.societyId,
          systemRole: widget.systemRole,
          onTabNavigate: (int index, [int? subTab]) =>
              _navigateToScreen(index, residentsSubTab: subTab),
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
          themeColor: Theme.of(context).colorScheme.primary,
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
        return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navItems = _modulesReady
        ? _buildNavItems()
        : [
            const FloatingNavItem(
                icon: Icons.dashboard_rounded, label: "Dashboard"),
            const FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
          ];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: List.generate(6, (index) => _buildScreen(index)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SocietyBottomNav(
              currentIndex: _modulesReady
                  ? _getCurrentTabIndex()
                  : (_currentIndex == 0 ? 0 : 1),
              onTap: _onBottomNavTap,
              showCenterButton: false,
              items: navItems,
            ),
          ),
        ],
      ),
    );
  }
}
