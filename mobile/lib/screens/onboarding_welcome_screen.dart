import 'dart:async';

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
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
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
                        _QuoteOfTheDayBubble(quoteFuture: _quoteFuture),
                      ],
                    ),
                    Column(
                      children: [
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
                  ],
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
              label: 'Security',
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
  static const String _titleText = 'Hey, I am Senti';

  late final AnimationController _aliveController;
  late final Animation<double> _bubbleLift;
  late final Animation<double> _bubbleScale;
  late final Animation<double> _titlePulse;

  Timer? _typeTimer;
  String _typedTitle = '';
  int _titleIndex = 0;

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

    _scheduleTypingTick(const Duration(milliseconds: 420));
  }

  void _scheduleTypingTick(Duration delay) {
    _typeTimer?.cancel();
    _typeTimer = Timer(delay, _onTypingTick);
  }

  void _onTypingTick() {
    if (!mounted) return;

    if (_titleIndex < _titleText.length) {
      setState(() {
        _titleIndex += 1;
        _typedTitle = _titleText.substring(0, _titleIndex);
      });
      _scheduleTypingTick(const Duration(milliseconds: 80));
    } else {
      _typeTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
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
            final showCursor = _typedTitle.length < _titleText.length;

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
                  child: _SentiCloudBubble(
                    title: _typedTitle,
                    showCursor: showCursor,
                    cursorOpacity: _titlePulse.value,
                    quote: quote,
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

class _SentiCloudBubble extends StatelessWidget {
  final String title;
  final bool showCursor;
  final double cursorOpacity;
  final String quote;

  const _SentiCloudBubble({
    required this.title,
    required this.showCursor,
    required this.cursorOpacity,
    required this.quote,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            height: 1.3,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (showCursor)
                        Opacity(
                          opacity: cursorOpacity,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Text(
                              '|',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                    ],
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
          Positioned(
            bottom: -8,
            left: 44,
            child: _cloudPuff(18),
          ),
          Positioned(
            bottom: -18,
            left: 26,
            child: _cloudPuff(10),
          ),
        ],
      ),
    );
  }

  Widget _cloudPuff(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border:
            Border.all(color: AppColors.primary.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
