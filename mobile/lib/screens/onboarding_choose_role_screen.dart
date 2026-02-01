import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import 'guard_login_screen.dart';
import 'resident_login_screen.dart';
import 'admin_login_screen.dart';

/// Choose Role screen: single theme (primary blue), cards with illustrations.
/// Tapping a card navigates to role-specific login screen.
class OnboardingChooseRoleScreen extends StatelessWidget {
  const OnboardingChooseRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: null, // No back button on this screen
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Illustration at top
            Center(
              child: Image.asset(
                'assets/illustrations/illustration_choose_role_guard.png',
                fit: BoxFit.contain,
                height: 180,
                errorBuilder: (_, __, ___) => Container(
                  height: 140,
                  width: 160,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Choose your role to continue',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Select how you\'ll use Sentinel',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.text2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _OnboardingRoleCard(
                      title: 'Guard',
                      subtitle: 'Manage visitor entries, approvals & logs',
                      illustrationPath: 'assets/illustrations/defense.png',
                      fallbackIcon: Icons.shield_rounded,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const GuardLoginScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _OnboardingRoleCard(
                      title: 'Resident',
                      subtitle: 'Approve or reject visitor requests',
                      illustrationPath: 'assets/illustrations/resident.png',
                      fallbackIcon: Icons.home_rounded,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ResidentLoginScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _OnboardingRoleCard(
                      title: 'Admin',
                      subtitle: 'Manage society, residents, guards & flats',
                      illustrationPath: 'assets/illustrations/admin.png',
                      fallbackIcon: Icons.admin_panel_settings_rounded,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminLoginScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingRoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String illustrationPath;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  const _OnboardingRoleCard({
    required this.title,
    required this.subtitle,
    required this.illustrationPath,
    required this.fallbackIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Illustration or placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.asset(
                    illustrationPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.primary.withOpacity(0.12),
                      child: Icon(
                        fallbackIcon,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
