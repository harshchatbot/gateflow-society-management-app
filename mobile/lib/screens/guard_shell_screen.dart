import 'package:flutter/material.dart';

import 'guard_dashboard_screen.dart';
import 'new_visitor_screen.dart';
import 'visitor_list_screen.dart';

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
    ),
    VisitorListScreen(guardId: widget.guardId),
    NewVisitorScreen(
      guardId: widget.guardId,
      guardName: widget.guardName,
      societyId: widget.societyId,
    ),
    _GuardProfileTab(guardName: widget.guardName),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: "Visitors",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: "New",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

/* -------- Simple Profile Placeholder -------- */

class _GuardProfileTab extends StatelessWidget {
  final String guardName;
  const _GuardProfileTab({required this.guardName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        guardName,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }
}
