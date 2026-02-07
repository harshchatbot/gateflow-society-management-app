import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../ui/app_colors.dart';
import '../services/quote_service.dart';
import '../widgets/sentinel_alive_mascot.dart';
import 'onboarding_choose_role_screen.dart';

/// Welcome screen: first screen of onboarding.
/// Light background, illustration, title, subtitle, Quote of the Day, Get Started → Choose Role.
class OnboardingWelcomeScreen extends StatefulWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  State<OnboardingWelcomeScreen> createState() =>
      _OnboardingWelcomeScreenState();
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      const _IllustrationPlaceholder(
                        assetPath:
                            'assets/illustrations/illustration_welcome.png',
                        semanticLabel: 'Person at desk',
                      ),
                      const SizedBox(height: 40),
                      Text(
                        'Welcome to Sentinel',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          letterSpacing: -0.6,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Secure Society Management',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      const _TrustStrip(),
                      const SizedBox(height: 24),
                      const Spacer(),
                      _QuoteOfTheDayBubble(quoteFuture: _quoteFuture),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const OnboardingChooseRoleScreen(),
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
                              textStyle: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            child: const Text('Get Started'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Made with ❤️ in Rajasthan, India',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2.withOpacity(0.85),
                            letterSpacing: 0.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            _TrustItem(
              icon: Icons.verified_user_outlined,
              label: 'OTP Login',
            ),
            _TrustItem(
              icon: Icons.notifications_active_outlined,
              label: 'Real-time Alerts',
            ),
            _TrustItem(
              icon: Icons.location_city_outlined,
              label: 'India-ready',
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// Quote of the Day: cloud-style bubble on top ("Hey, I am Senti" + quote), SENTI mascot below (bottom center, slightly bigger).
class _QuoteOfTheDayBubble extends StatefulWidget {
  final Future<String> quoteFuture;

  const _QuoteOfTheDayBubble({required this.quoteFuture});

  @override
  State<_QuoteOfTheDayBubble> createState() => _QuoteOfTheDayBubbleState();
}

class _QuoteOfTheDayBubbleState extends State<_QuoteOfTheDayBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _aliveController;
  late final Animation<double> _bubbleLift;
  late final Animation<double> _bubbleScale;
  late final Animation<double> _titlePulse;

  @override
  void initState() {
    super.initState();
    _aliveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _bubbleLift = Tween<double>(begin: 0, end: -7).animate(
      CurvedAnimation(parent: _aliveController, curve: Curves.easeInOut),
    );
    _bubbleScale = Tween<double>(begin: 1, end: 1.015).animate(
      CurvedAnimation(parent: _aliveController, curve: Curves.easeInOutSine),
    );
    _titlePulse = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: _aliveController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _aliveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FutureBuilder<String>(
          future: widget.quoteFuture,
          builder: (context, snapshot) {
            final quote = snapshot.hasData && snapshot.data!.isNotEmpty
                ? snapshot.data!
                : kPlaceholderQuote;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _aliveController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _bubbleLift.value),
                      child: Transform.scale(
                        scale: _bubbleScale.value,
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
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
                        AnimatedBuilder(
                          animation: _aliveController,
                          builder: (context, child) => Opacity(
                            opacity: _titlePulse.value,
                            child: child,
                          ),
                          child: Text(
                            'Hey, I am Senti',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              height: 1.3,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOut,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                            height: 1.45,
                            letterSpacing: 0.15,
                          ),
                          child: Text(
                            quote,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const SentinelAliveMascot(
                  mood: AliveMascotMood.namaste,
                  size: 176,
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
