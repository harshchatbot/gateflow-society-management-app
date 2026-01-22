import 'package:flutter/material.dart';

import '../ui/floating_bottom_nav.dart'; // the file where SocietyBottomNav lives

import 'resident_dashboard_screen.dart';
import 'resident_approvals_screen.dart';
import 'resident_history_screen.dart';
import 'resident_profile_screen.dart';

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

  late final List<Widget> _screens = [
    ResidentDashboardScreen(
      residentId: widget.residentId,
      residentName: widget.residentName,
      societyId: widget.societyId,
      flatNo: widget.flatNo,
    ),
    ResidentApprovalsScreen(
      residentId: widget.residentId,
      societyId: widget.societyId,
      flatNo: widget.flatNo,
    ),
    ResidentHistoryScreen(
      residentId: widget.residentId,
      societyId: widget.societyId,
      flatNo: widget.flatNo,
    ),
    ResidentProfileScreen(
      residentId: widget.residentId,
      residentName: widget.residentName,
      societyId: widget.societyId,
      flatNo: widget.flatNo,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: SocietyBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        showCenterButton: false, // ✅ Resident: no FAB
        items: const [
          FloatingNavItem(icon: Icons.home_rounded, label: "Home"),
          FloatingNavItem(icon: Icons.verified_rounded, label: "Approvals"),
          FloatingNavItem(icon: Icons.history_rounded, label: "History"),
          FloatingNavItem(icon: Icons.person_rounded, label: "Profile"),
        ],
      ),
    );
  }
}
