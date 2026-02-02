import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../services/quote_service.dart';
import 'onboarding_choose_role_screen.dart';

/// Welcome screen: first screen of onboarding.
/// Light background, illustration, title, subtitle, Quote of the Day, Get Started → Choose Role.
class OnboardingWelcomeScreen extends StatefulWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  State<OnboardingWelcomeScreen> createState() => _OnboardingWelcomeScreenState();
}

class _OnboardingWelcomeScreenState extends State<OnboardingWelcomeScreen> {
  late final Future<String> _quoteFuture;

  @override
  void initState() {
    super.initState();
    _quoteFuture = QuoteService().getQuoteOfTheDay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
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
            const SizedBox(height: 24),
            const Spacer(),
            _QuoteOfTheDayBubble(quoteFuture: _quoteFuture),
            const SizedBox(height: 24),
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

/// Quote of the Day: cloud-style bubble on top ("Hey, I am Senti" + quote), SENTI mascot below (bottom center, slightly bigger).
class _QuoteOfTheDayBubble extends StatelessWidget {
  final Future<String> quoteFuture;

  const _QuoteOfTheDayBubble({required this.quoteFuture});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FutureBuilder<String>(
          future: quoteFuture,
          builder: (context, snapshot) {
            final quote = snapshot.hasData && snapshot.data!.isNotEmpty
                ? snapshot.data!
                : kPlaceholderQuote;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 2),
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hey, I am Senti',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        quote,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text2,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 152,
                  height: 152,
                  child: Image.asset(
                    'assets/mascot/senti_namaste.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.pets_rounded,
                      size: 72,
                      color: AppColors.primary.withOpacity(0.5),
                    ),
                  ),
                ),
              ],
            );
          },
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
