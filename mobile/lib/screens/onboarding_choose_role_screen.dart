import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../core/session_gate_service.dart';
import 'guard_login_screen.dart';
import 'resident_login_screen.dart';
import 'admin_login_screen.dart';
import 'phone_otp_login_screen.dart';
import 'how_sentinel_works_screen.dart';

/// Choose Role screen: single theme (primary blue), cards with illustrations.
/// Used after logout and from onboarding. Shows gate block message if set.
class OnboardingChooseRoleScreen extends StatefulWidget {
  const OnboardingChooseRoleScreen({super.key});

  @override
  State<OnboardingChooseRoleScreen> createState() => _OnboardingChooseRoleScreenState();
}

class _OnboardingChooseRoleScreenState extends State<OnboardingChooseRoleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = GateBlockMessage.take();
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

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
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Choose your role to continue',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
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
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HowSentinelWorksScreen(),
                  ),
                );
              },
              icon: Icon(Icons.info_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              label: Text(
                'How Sentinel Works',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                        // Phone OTP is primary for residents.
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PhoneOtpLoginScreen(
                              roleHint: 'resident',
                            ),
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
            color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
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
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      child: Icon(
                        fallbackIcon,
                        size: 36,
                        color: Theme.of(context).colorScheme.primary,
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
