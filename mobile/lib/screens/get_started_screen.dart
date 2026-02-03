import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

/// Post-login "Get Started" screen: Quick Start (role-based) + Interactive Tour button.
/// Entry from Profile/Drawer/Menu for each role.
class GetStartedScreen extends StatelessWidget {
  final String role;
  final VoidCallback? onStartTour;

  const GetStartedScreen({
    super.key,
    required this.role,
    this.onStartTour,
  });

  String get _roleTitle {
    switch (role.toLowerCase()) {
      case 'guard':
        return 'Guard';
      case 'resident':
        return 'Resident';
      case 'admin':
      case 'super_admin':
        return 'Admin';
      default:
        return 'User';
    }
  }

  /// Role accent: Resident keeps success green; Guard/Admin use theme primary (no blue).
  Color _themeColor(BuildContext context) {
    if (role.toLowerCase() == 'resident') return AppColors.success;
    return Theme.of(context).colorScheme.primary;
  }

  List<Map<String, String>> _quickStartSteps() {
    switch (role.toLowerCase()) {
      case 'guard':
        return [
          {'title': 'New Visitor Entry', 'body': 'Use the center button or "New Entry" to register a visitor. Resident gets a request to approve.'},
          {'title': 'Visitor List / History', 'body': 'View today\'s visitors and full history. Tap a visitor to see details.'},
          {'title': 'SOS Alerts', 'body': 'When a resident sends SOS, you get a notification. Open SOS Alerts to view and respond.'},
        ];
      case 'resident':
        return [
          {'title': 'Approve / Reject Visitors', 'body': 'Open Approvals to see pending visitor requests. Approve or reject from there.'},
          {'title': 'Emergency SOS', 'body': 'Use SOS on your dashboard to send an instant alert to security and admin.'},
          {'title': 'Complaints', 'body': 'Raise or view complaints from the Complaints tab.'},
        ];
      case 'admin':
      case 'super_admin':
        return [
          {'title': 'Approve Residents', 'body': 'Residents Directory: approve pending signups and manage resident list.'},
          {'title': 'Share Society Code / QR', 'body': 'Security Staff: generate Guard Join QR so guards can join your society.'},
          {'title': 'Create Notice', 'body': 'Notice Board: create and manage society notices.'},
          {'title': 'Complaints & SOS', 'body': 'Complaints tab for issues; SOS Alerts for emergency responses.'},
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _quickStartSteps();
    final roleColor = _themeColor(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: roleColor,
        foregroundColor: theme.colorScheme.onPrimary,
        title: const Text(
          'Get Started',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Start — $_roleTitle',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...steps.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['title']!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: roleColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s['body']!,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onStartTour?.call();
                },
                icon: const Icon(Icons.touch_app_rounded, size: 22),
                label: const Text(
                  'Start Interactive Tour',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: roleColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
