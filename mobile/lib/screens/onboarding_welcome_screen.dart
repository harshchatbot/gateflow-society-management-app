import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import 'onboarding_choose_role_screen.dart';

/// Welcome screen: first screen of onboarding.
/// Light background, illustration, title, subtitle, Get Started → Choose Role.
class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Illustration placeholder (swap with real SVG/PNG)
            _IllustrationPlaceholder(
              assetPath: 'assets/illustrations/illustration_welcome.png',
              semanticLabel: 'Person at desk',
            ),
            const SizedBox(height: 40),
            const Text(
              'Welcome to Sentinel',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Secure Society Management',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const OnboardingChooseRoleScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Get Started'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable placeholder for illustrations; falls back to icon if asset missing.
class _IllustrationPlaceholder extends StatelessWidget {
  final String assetPath;
  final String semanticLabel;

  const _IllustrationPlaceholder({
    required this.assetPath,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: 280,
        height: 220,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.person_rounded,
              size: 100,
              color: AppColors.primary.withOpacity(0.4),
            ),
          ),
        ),
      ),
    );
  }
}
