import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// Screens
import 'guard_dashboard_screen.dart';
import 'new_visitor_screen.dart';
import 'visitor_list_screen.dart';
import 'guard_history_screen.dart';

// UI logic
import '../ui/app_colors.dart'; 
import '../ui/floating_bottom_nav.dart'; // Use shared SocietyBottomNav
import 'guard_profile_screen.dart';
import '../services/notification_service.dart';



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

  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
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

  late final List<Widget> _screens = [
    GuardDashboardScreen(
      key: _dashboardKey,
      guardId: widget.guardId,
      guardName: widget.guardName,
      societyId: widget.societyId,
      onTapNewEntry: () => setState(() => _index = 2),
      onTapVisitors: () => setState(() => _index = 1),
    ),
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
    ProfileScreen(
      guardId: widget.guardId,
      guardName: widget.guardName,
      societyId: widget.societyId,
      onBackPressed: () => setState(() => _index = 0),
      onStartTourRequested: _onStartTourRequested,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: _screens,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SocietyBottomNav(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              showCenterButton: true, // Guard has center FAB button
              centerIndex: 2, // Entry screen
              centerIcon: Icons.qr_code_scanner,
              items: const [
                FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
                FloatingNavItem(icon: Icons.groups_rounded, label: "Visitors"),
                FloatingNavItem(icon: Icons.qr_code_scanner, label: "Entry"), // Center button
                FloatingNavItem(icon: Icons.history_rounded, label: "History"),
                FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}