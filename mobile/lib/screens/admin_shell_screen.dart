import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          AdminDashboardScreen(
            adminId: widget.adminId,
            adminName: widget.adminName,
            societyId: widget.societyId,
          ),
          // TODO: Add other admin screens here
          Center(child: Text("Manage Residents (Coming Soon)", style: TextStyle(color: AppColors.text2))),
          Center(child: Text("Manage Guards (Coming Soon)", style: TextStyle(color: AppColors.text2))),
          Center(child: Text("Visitor Logs (Coming Soon)", style: TextStyle(color: AppColors.text2))),
        ],
      ),
      bottomNavigationBar: SocietyBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        items: const [
          FloatingNavItem(icon: Icons.dashboard_rounded, label: "Dashboard"),
          FloatingNavItem(icon: Icons.people_rounded, label: "Residents"),
          FloatingNavItem(icon: Icons.shield_rounded, label: "Guards"),
          FloatingNavItem(icon: Icons.history_rounded, label: "Logs"),
        ],
      ),
    );
  }
}
