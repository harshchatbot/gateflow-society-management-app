import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/sentinel_theme.dart';

/// Static pre-signup info screen: "How Sentinel Works".
/// Explains onboarding in 4–5 steps and highlights SOS as a USP.
/// No backend; accessible from OnboardingChooseRoleScreen.
class HowSentinelWorksScreen extends StatelessWidget {
  const HowSentinelWorksScreen({super.key});

  static const List<_StepItem> _steps = [
    _StepItem(
      title: 'Choose your role',
      body: 'Guard, Resident, or Admin. Each role gets a tailored journey.',
      icon: Icons.badge_outlined,
    ),
    _StepItem(
      title: 'Join or create your society',
      body:
          'Residents/Admins use society code. Guards join with admin-generated code.',
      icon: Icons.groups_outlined,
    ),
    _StepItem(
      title: 'Get approved',
      body:
          'Admin approval activates access. Pending users see clear waiting status.',
      icon: Icons.verified_user_outlined,
    ),
    _StepItem(
      title: 'Use role dashboards',
      body:
          'Visitors, complaints, notices, and alerts are available by your role.',
      icon: Icons.dashboard_outlined,
    ),
    _StepItem(
      title: 'Emergency SOS',
      body:
          'Residents can send SOS instantly; security and admins are alerted right away.',
      icon: Icons.sos_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'How Sentinel Works',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sentinel in 5 simple steps',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'From onboarding to emergency response, everything is built for fast society operations.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TagChip(label: 'OTP Login'),
                      _TagChip(label: 'Role-based Access'),
                      _TagChip(label: 'Real-time Alerts'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(
              _steps.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StepCard(
                  stepNumber: index + 1,
                  item: _steps[index],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SentinelStatusPalette.bg(AppColors.error),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: SentinelStatusPalette.border(AppColors.error)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sos_rounded, color: AppColors.error, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SOS is prioritized in Sentinel. One tap sends alerts to your society team instantly.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepItem {
  final String title;
  final String body;
  final IconData icon;

  const _StepItem({
    required this.title,
    required this.body,
    required this.icon,
  });
}

class _StepCard extends StatelessWidget {
  final int stepNumber;
  final _StepItem item;

  const _StepCard({
    required this.stepNumber,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(item.icon, size: 17, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.body,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
