import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../ui/floating_bottom_nav.dart';
import '../ui/sentinel_theme.dart';

import 'resident_dashboard_screen.dart';
import 'resident_approvals_screen.dart';
import 'resident_history_screen.dart';
import 'resident_complaints_list_screen.dart';
import 'resident_profile_screen.dart';
import 'notice_board_screen.dart';
import '../services/notification_service.dart';
import '../core/society_modules.dart';

class ResidentShellScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;

  const ResidentShellScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentShellScreen> createState() => _ResidentShellScreenState();
}

class _ResidentShellScreenState extends State<ResidentShellScreen> {
  int _index = 0;
  final GlobalKey<State<ResidentDashboardScreen>> _dashboardKey = GlobalKey<State<ResidentDashboardScreen>>();
  bool _modulesReady = false;


  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
    SocietyModules.refresh(widget.societyId).then((_) {
      if (mounted) setState(() => _modulesReady = true);
    });
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

  Future<void> _subscribeToNotifications() async {
    try {
      final notificationService = NotificationService();
      final normalizedFlatNo = widget.flatNo.trim().toUpperCase();
      await notificationService.subscribeUserTopics(
        societyId: widget.societyId,
        // Use flat label/key for visitor-entry topic subscription.
        flatId: normalizedFlatNo,
        role: "resident",
      );
    } catch (e) {
      // Notification subscription failed, continue anyway
      AppLogger.e("Failed to subscribe resident notification topics", error: e);
      if (kDebugMode) {
        debugPrint("Failed to subscribe to notifications: $e");
      }
    }
  }

  List<Widget> _buildScreens() {
    final hasVisitor = SocietyModules.isEnabled(SocietyModuleIds.visitorManagement);
    final hasComplaints = SocietyModules.isEnabled(SocietyModuleIds.complaints);
    final hasNotices = SocietyModules.isEnabled(SocietyModuleIds.notices);
    final complaintsIdx = hasVisitor ? 3 : 1;
    final noticesIdx = hasVisitor ? (hasComplaints ? 4 : 3) : (hasComplaints ? 2 : 1);

    return [
      ResidentDashboardScreen(
        key: _dashboardKey,
        residentId: widget.residentId,
        residentName: widget.residentName,
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        onNavigateToApprovals: hasVisitor ? () => setState(() => _index = 1) : null,
        onNavigateToHistory: hasVisitor ? () => setState(() => _index = 2) : null,
        onNavigateToComplaints: hasComplaints ? () => setState(() => _index = complaintsIdx) : null,
        onNavigateToNotices: hasNotices ? () => setState(() => _index = noticesIdx) : null,
      ),
      if (hasVisitor) ...[
        ResidentApprovalsScreen(
          residentId: widget.residentId,
          societyId: widget.societyId,
          flatNo: widget.flatNo,
          onBackPressed: () => setState(() => _index = 0),
        ),
        ResidentHistoryScreen(
          residentId: widget.residentId,
          societyId: widget.societyId,
          flatNo: widget.flatNo,
          onBackPressed: () => setState(() => _index = 0),
        ),
      ],
      if (hasComplaints)
        ResidentComplaintsListScreen(
          residentId: widget.residentId,
          societyId: widget.societyId,
          flatNo: widget.flatNo,
          onBackPressed: () => setState(() => _index = 0),
        ),
      if (hasNotices)
        NoticeBoardScreen(
          societyId: widget.societyId,
          themeColor: Theme.of(context).colorScheme.primary,
          useScaffold: false,
          onBackPressed: () => setState(() => _index = 0),
        ),
      ResidentProfileScreen(
        residentId: widget.residentId,
        residentName: widget.residentName,
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        onBackPressed: () => setState(() => _index = 0),
        onStartTourRequested: _onStartTourRequested,
      ),
    ];
  }

  List<FloatingNavItem> _buildNavItems() {
    final hasVisitor = SocietyModules.isEnabled(SocietyModuleIds.visitorManagement);
    final hasComplaints = SocietyModules.isEnabled(SocietyModuleIds.complaints);
    final hasNotices = SocietyModules.isEnabled(SocietyModuleIds.notices);
    final items = <FloatingNavItem>[
      const FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
    ];
    if (hasVisitor) {
      items.add(const FloatingNavItem(icon: Icons.verified_rounded, label: "Approvals"));
      items.add(const FloatingNavItem(icon: Icons.history_rounded, label: "History"));
    }
    if (hasComplaints) {
      items.add(const FloatingNavItem(icon: Icons.report_problem_rounded, label: "Complaints"));
    }
    if (hasNotices) {
      items.add(const FloatingNavItem(icon: Icons.notifications_rounded, label: "Notices"));
    }
    items.add(const FloatingNavItem(icon: Icons.person_rounded, label: "Profile"));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final screens = _modulesReady ? _buildScreens() : [
      ResidentDashboardScreen(
        key: _dashboardKey,
        residentId: widget.residentId,
        residentName: widget.residentName,
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        onNavigateToApprovals: null,
        onNavigateToHistory: null,
        onNavigateToComplaints: null,
        onNavigateToNotices: null,
      ),
      ResidentProfileScreen(
        residentId: widget.residentId,
        residentName: widget.residentName,
        societyId: widget.societyId,
        flatNo: widget.flatNo,
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
          screens[clampedIndex],
          Align(
            alignment: Alignment.bottomCenter,
            child: SocietyBottomNav(
              currentIndex: clampedIndex,
              onTap: (i) => setState(() => _index = i),
              showCenterButton: false,
              items: navItems,
              selectedItemColor: SentinelColors.sentinelAccent,
            ),
          ),
        ],
      ),
    );
  }
}
