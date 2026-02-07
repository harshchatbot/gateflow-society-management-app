import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// Screens
import 'guard_dashboard_screen.dart';
import 'new_visitor_screen.dart';
import 'visitor_list_screen.dart';
import 'guard_history_screen.dart';

// UI logic
import '../ui/floating_bottom_nav.dart'; // Use shared SocietyBottomNav
import 'guard_profile_screen.dart';
import '../services/notification_service.dart';
import '../core/society_modules.dart';



class GuardShellScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;

  const GuardShellScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
  });

  @override
  State<GuardShellScreen> createState() => _GuardShellScreenState();
}

class _GuardShellScreenState extends State<GuardShellScreen> {
  int _index = 0;
  final GlobalKey<State<GuardDashboardScreen>> _dashboardKey = GlobalKey<State<GuardDashboardScreen>>();
  bool _modulesReady = false;

  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
    SocietyModules.refresh(widget.societyId).then((_) {
      if (mounted) {
        setState(() {
          _modulesReady = true;
          // If we were on Profile (index 1) in 2-screen layout, map to Profile in 5-screen
          if (_index == 1 && SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
            _index = 4;
          }
        });
      }
    });
  }

  Future<void> _subscribeToNotifications() async {
    try {
      final notificationService = NotificationService();
      await notificationService.subscribeUserTopics(
        societyId: widget.societyId,
        role: "guard",
      );
    } catch (e) {
      // Notification subscription failed, continue anyway
      if (kDebugMode) {
        debugPrint("Failed to subscribe to notifications: $e");
      }
    }
  }

  void _onStartTourRequested() {
    setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        try {
          (_dashboardKey.currentState as dynamic)?.startTour();
        } catch (_) {}
      });
    });
  }

  List<Widget> _buildScreens() {
    final hasVisitor = SocietyModules.isEnabled(SocietyModuleIds.visitorManagement);
    return [
      GuardDashboardScreen(
        key: _dashboardKey,
        guardId: widget.guardId,
        guardName: widget.guardName,
        societyId: widget.societyId,
        onTapNewEntry: hasVisitor ? () => setState(() => _index = 2) : null,
        onTapVisitors: hasVisitor ? () => setState(() => _index = 1) : null,
      ),
      if (hasVisitor) ...[
        VisitorListScreen(
          guardId: widget.guardId,
          onBackPressed: () => setState(() => _index = 0),
        ),
        NewVisitorScreen(
          guardId: widget.guardId,
          guardName: widget.guardName,
          societyId: widget.societyId,
          onBackPressed: () => setState(() => _index = 0),
        ),
        GuardHistoryScreen(
          guardId: widget.guardId,
          onBackPressed: () => setState(() => _index = 0),
        ),
      ],
      ProfileScreen(
        guardId: widget.guardId,
        guardName: widget.guardName,
        societyId: widget.societyId,
        onBackPressed: () => setState(() => _index = 0),
        onStartTourRequested: _onStartTourRequested,
      ),
    ];
  }

  List<FloatingNavItem> _buildNavItems() {
    final hasVisitor = SocietyModules.isEnabled(SocietyModuleIds.visitorManagement);
    if (!hasVisitor) {
      return const [
        FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
        FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
      ];
    }
    return const [
      FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
      FloatingNavItem(icon: Icons.groups_rounded, label: "Visitors"),
      FloatingNavItem(icon: Icons.qr_code_scanner, label: "Entry"),
      FloatingNavItem(icon: Icons.history_rounded, label: "History"),
      FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
    ];
  }

  int _getProfileIndex() {
    return SocietyModules.isEnabled(SocietyModuleIds.visitorManagement) ? 4 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final hasVisitor = _modulesReady && SocietyModules.isEnabled(SocietyModuleIds.visitorManagement);
    final screens = _modulesReady ? _buildScreens() : [
      GuardDashboardScreen(
        key: _dashboardKey,
        guardId: widget.guardId,
        guardName: widget.guardName,
        societyId: widget.societyId,
        onTapNewEntry: null,
        onTapVisitors: null,
      ),
      ProfileScreen(
        guardId: widget.guardId,
        guardName: widget.guardName,
        societyId: widget.societyId,
        onBackPressed: () => setState(() => _index = 0),
        onStartTourRequested: _onStartTourRequested,
      ),
    ];
    if (_index >= screens.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = 0);
      });
    }
    final clampedIndex = _index.clamp(0, screens.length - 1);
    final navItems = _modulesReady ? _buildNavItems() : const [
      FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
      FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
    ];
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: clampedIndex,
            children: screens,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SocietyBottomNav(
              currentIndex: clampedIndex,
              onTap: (i) => setState(() => _index = i),
              showCenterButton: hasVisitor,
              centerIndex: hasVisitor ? 2 : 1,
              centerIcon: Icons.qr_code_scanner,
              items: navItems,
            ),
          ),
        ],
      ),
    );
  }
}