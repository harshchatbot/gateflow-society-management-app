import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/sentinel_theme.dart';

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
          {
            'title': 'New Visitor Entry',
            'body':
                'Use the center button or "New Entry" to register a visitor. Resident gets a request to approve.'
          },
          {
            'title': 'Visitor List / History',
            'body':
                'View today\'s visitors and full history. Tap a visitor to see details.'
          },
          {
            'title': 'SOS Alerts',
            'body':
                'When a resident sends SOS, you get a notification. Open SOS Alerts to view and respond.'
          },
        ];
      case 'resident':
        return [
          {
            'title': 'Approve / Reject Visitors',
            'body':
                'Open Approvals to see pending visitor requests. Approve or reject from there.'
          },
          {
            'title': 'Emergency SOS',
            'body':
                'Use SOS on your dashboard to send an instant alert to security and admin.'
          },
          {
            'title': 'Complaints',
            'body': 'Raise or view complaints from the Complaints tab.'
          },
        ];
      case 'admin':
      case 'super_admin':
        return [
          {
            'title': 'Approve Residents',
            'body':
                'Residents Directory: approve pending signups and manage resident list.'
          },
          {
            'title': 'Share Society Code / QR',
            'body':
                'Security Staff: generate Guard Join QR so guards can join your society.'
          },
          {
            'title': 'Create Notice',
            'body': 'Notice Board: create and manage society notices.'
          },
          {
            'title': 'Complaints & SOS',
            'body':
                'Complaints tab for issues; SOS Alerts for emergency responses.'
          },
        ];
      default:
        return [];
    }
  }

  IconData _roleIcon() {
    switch (role.toLowerCase()) {
      case 'guard':
        return Icons.shield_outlined;
      case 'resident':
        return Icons.home_outlined;
      case 'admin':
      case 'super_admin':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outline_rounded;
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
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Get Started',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_roleIcon(), color: roleColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Start — $_roleTitle',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Follow these steps to get productive in under 2 minutes.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(
              steps.length,
              (index) {
                final step = steps[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: roleColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step['title']!,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                step['body']!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: roleColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Maybe later'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tip: You can reopen this anytime from your profile/help menu.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: SentinelColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
