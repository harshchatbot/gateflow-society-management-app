import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
import 'admin_manage_residents_screen.dart';
import 'admin_manage_guards_screen.dart';
import 'admin_manage_complaints_screen.dart';
import 'admin_profile_screen.dart';
import 'notice_board_screen.dart';
import '../ui/app_colors.dart';
import '../ui/floating_bottom_nav.dart';

/// Admin Shell Screen
/// 
/// Main container for admin navigation with bottom nav
class AdminShellScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String role;

  const AdminShellScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.role,
  });

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;
  final Map<int, bool> _screenInitialized = {}; // Track which screens have been initialized

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      // Mark screen as initialized when first viewed
      _screenInitialized[index] = true;
    });
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
          adminId: widget.adminId,
          adminName: widget.adminName,
          societyId: widget.societyId,
          onTabNavigate: _onTabChanged,
        );
      case 1:
        return AdminManageResidentsScreen(
          adminId: widget.adminId,
          societyId: widget.societyId,
        );
      case 2:
        return AdminManageGuardsScreen(
          adminId: widget.adminId,
          societyId: widget.societyId,
        );
      case 3:
        return AdminManageComplaintsScreen(
          adminId: widget.adminId,
          societyId: widget.societyId,
        );
      case 4:
        return NoticeBoardScreen(
          societyId: widget.societyId,
          themeColor: AppColors.admin,
          adminId: widget.adminId, // Pass admin ID so manage button shows
          adminName: widget.adminName,
          useScaffold: false, // Don't use Scaffold when used as tab
        );
      case 5:
        return AdminProfileScreen(
          adminId: widget.adminId,
          adminName: widget.adminName,
          societyId: widget.societyId,
          role: widget.role,
        );
      default:
        return Container(color: AppColors.bg);
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize dashboard immediately
    _screenInitialized[0] = true;
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
        currentIndex: _currentIndex,
        onTap: _onTabChanged,
        showCenterButton: false, // No center button for admin
        items: const [
          FloatingNavItem(icon: Icons.dashboard_rounded, label: "Dashboard"),
          FloatingNavItem(icon: Icons.people_rounded, label: "Residents"),
          FloatingNavItem(icon: Icons.shield_rounded, label: "Guards"),
          FloatingNavItem(icon: Icons.report_problem_rounded, label: "Complaints"),
          FloatingNavItem(icon: Icons.notifications_rounded, label: "Notices"),
          FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
        ],
      ),
    );
  }
}
