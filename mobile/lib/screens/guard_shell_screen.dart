import 'dart:ui';
import 'package:flutter/material.dart';

// Screens
import 'guard_dashboard_screen.dart';
import 'new_visitor_screen.dart';
import 'visitor_list_screen.dart';

// UI logic
import '../ui/app_colors.dart'; 
import 'guard_profile_screen.dart';
import 'guard_login_screen.dart';



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

  late final List<Widget> _screens = [
    GuardDashboardScreen(
      guardId: widget.guardId,
      guardName: widget.guardName,
      societyId: widget.societyId,
      onTapNewEntry: () => setState(() => _index = 2),
      onTapVisitors: () => setState(() => _index = 1),
    ),
    VisitorListScreen(guardId: widget.guardId),
    NewVisitorScreen(
      guardId: widget.guardId,
      guardName: widget.guardName,
      societyId: widget.societyId,
    ),
    const Center(child: Text("History Screen")), // Added 4th screen
    ProfileScreen( // ✅ Removed the 'onLogout' parameter
        guardId: widget.guardId,
        guardName: widget.guardName,
        societyId: widget.societyId,
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
              items: const [
                FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
                FloatingNavItem(icon: Icons.groups_rounded, label: "Visitors"),
                FloatingNavItem(icon: Icons.qr_code_scanner, label: "Entry"),
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

/* -----------------------------------------------------------
   CLEAN UI COMPONENTS (Using AppColors)
----------------------------------------------------------- */

class FloatingNavItem {
  final IconData icon;
  final String label;
  const FloatingNavItem({required this.icon, required this.label});
}

class SocietyBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavItem> items;

  const SocietyBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      height: 85,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Glass Background using AppColors
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(35),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.text.withOpacity(0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _buildTab(0)),
                      Expanded(child: _buildTab(1)),
                      const SizedBox(width: 85), 
                      Expanded(child: _buildTab(3)),
                      Expanded(child: _buildTab(4)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Floating Center Button
          Positioned(
            top: 0, 
            child: GestureDetector(
              onTap: () => onTap(2),
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF1E40AF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 34),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index) {
    bool isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            items[index].icon,
            color: isSelected ? AppColors.primary : AppColors.text2,
            size: 26,
          ),
          const SizedBox(height: 3),
          Text(
            items[index].label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isSelected ? AppColors.primary : AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}