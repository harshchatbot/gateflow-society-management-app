import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../ui/app_colors.dart';
import 'role_select_screen.dart';
import 'onboarding_welcome_screen.dart';
import 'guard_shell_screen.dart';
import 'resident_shell_screen.dart';
import 'admin_shell_screen.dart';
import '../core/storage.dart';
import '../core/society_modules.dart';
import '../services/firestore_service.dart';
import '../core/session_gate_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _logoRotation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    // Main animation controller (3 seconds)
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Pulse controller for breathing effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Shimmer controller for glow effect
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Logo scale animation (elastic bounce in)
    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.3).chain(
          CurveTween(curve: Curves.elasticOut),
        ),
        weight: 0.5,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 0.3,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Logo fade in
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Logo rotation animation (subtle entrance spin)
    _logoRotation = Tween<double>(begin: -0.2, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // Pulse animation (breathing effect)
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Shimmer/glow animation
    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut,
      ),
    );

    // Glow intensity animation
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: 0.3,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.7),
        weight: 0.7,
      ),
    ]).animate(_mainController);

    // Text fade and slide animation (staggered)
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _mainController.forward();
    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    // Wait for animation to complete
    await Future.delayed(const Duration(milliseconds: 3000));

    if (!mounted) return;

    Widget? targetScreen;

    try {
      // Check Firebase Auth first — run post-login gate (membership + society active)
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          final gate = SessionGateService();
          final gateResult = await gate.validateSessionAfterLogin(firebaseUser.uid).timeout(
            const Duration(seconds: 5),
            onTimeout: () => GateResult.blocked(
              GateBlockReason.membershipNotFound,
              'This society is currently inactive. Please contact the society admin.',
            ),
          );

          if (gateResult.allowed && gateResult.memberInfo != null && mounted) {
            final membership = gateResult.memberInfo!;
            final societyId = membership['societyId'] as String? ?? '';
            if (societyId.isNotEmpty) {
              await SocietyModules.ensureLoaded(societyId);
            }
            final systemRole = membership['systemRole'] as String? ?? '';
            final name = membership['name'] as String? ?? '';
            final flatNo = membership['flatNo'] as String?;
            final societyRole = membership['societyRole'] as String?;

            if (systemRole == 'admin' && societyId.isNotEmpty) {
              targetScreen = AdminShellScreen(
                adminId: firebaseUser.uid,
                adminName: name.isNotEmpty ? name : "Admin",
                societyId: societyId,
                role: societyRole ?? 'ADMIN',
              );
            } else if (systemRole == 'guard' && societyId.isNotEmpty) {
              targetScreen = GuardShellScreen(
                guardId: firebaseUser.uid,
                guardName: name.isNotEmpty ? name : "Guard",
                societyId: societyId,
              );
            } else if (systemRole == 'resident' && flatNo != null && societyId.isNotEmpty) {
              targetScreen = ResidentShellScreen(
                residentId: firebaseUser.uid,
                residentName: name.isNotEmpty ? name : "Resident",
                societyId: societyId,
                flatNo: flatNo,
              );
            }
          }

          if (!gateResult.allowed && mounted) {
            try {
              await FirebaseAuth.instance.signOut();
              await Storage.clearAllSessions();
              await Storage.clearFirebaseSession();
              SocietyModules.clear();
              GateBlockMessage.set(gateResult.userMessage ?? 'This society is currently inactive. Please contact the society admin.');
            } catch (_) {}
            targetScreen = const RoleSelectScreen();
          }
        } catch (e, stackTrace) {
          if (kDebugMode) {
            debugPrint("Error in splash gate: $e");
            debugPrint("Stack trace: $stackTrace");
          }
          try {
            await FirebaseAuth.instance.signOut();
            await Storage.clearAllSessions();
            await Storage.clearFirebaseSession();
            SocietyModules.clear();
          } catch (_) {}
        }
      }

      // Fallback to old session storage if Firebase didn't work
      if (targetScreen == null && mounted) {
        try {
          final residentSession = await Storage.getResidentSession();
          final guardSession = await Storage.getGuardSession();
          final adminSession = await Storage.getAdminSession();

          if (residentSession != null) {
            await SocietyModules.ensureLoaded(residentSession.societyId);
            targetScreen = ResidentShellScreen(
              residentId: residentSession.residentId,
              residentName: residentSession.residentName,
              societyId: residentSession.societyId,
              flatNo: residentSession.flatNo,
            );
          } else if (guardSession != null) {
            await SocietyModules.ensureLoaded(guardSession.societyId);
            targetScreen = GuardShellScreen(
              guardId: guardSession.guardId,
              guardName: guardSession.guardName.isNotEmpty
                  ? guardSession.guardName
                  : "Guard",
              societyId: guardSession.societyId.isNotEmpty
                  ? guardSession.societyId
                  : "Society",
            );
          } else if (adminSession != null) {
            await SocietyModules.ensureLoaded(adminSession.societyId);
            targetScreen = AdminShellScreen(
              adminId: adminSession.adminId,
              adminName: adminSession.adminName,
              societyId: adminSession.societyId,
              role: adminSession.role,
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint("Error loading old session: $e");
          }
        }
      }

      // Final fallback: go to onboarding welcome (first-time / not logged in)
      if (targetScreen == null) {
        targetScreen = const OnboardingWelcomeScreen();
      }

      // Navigate to target screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => targetScreen!),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("Critical error in splash navigation: $e");
        debugPrint("Stack trace: $stackTrace");
      }
      // Ensure we always navigate somewhere
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingWelcomeScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFFE5E5), // soft leaf-red glow
              AppColors.bg,
              AppColors.bg,
              const Color(0xFFFFF0F0),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo with multiple effects
              AnimatedBuilder(
                animation: Listenable.merge([
                  _mainController,
                  _pulseController,
                  _shimmerController,
                ]),
                builder: (context, child) {
                  return Transform.scale(
                    scale: _logoScale.value * _pulseAnimation.value,
                    child: Transform.rotate(
                      angle: _logoRotation.value,
                      child: Opacity(
                        opacity: _logoFade.value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow effect
                            if (_glowAnimation.value > 0)
                              Container(
                                width: 260 * _logoScale.value,
                                height: 260 * _logoScale.value,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF6F61).withOpacity(
                                        0.35 * _glowAnimation.value * (0.5 + 0.5 * _shimmerAnimation.value),
                                      ),
                                      blurRadius: 50 * _glowAnimation.value,
                                      spreadRadius: 14 * _glowAnimation.value,
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFFFF8A80).withOpacity(
                                        0.25 * _glowAnimation.value * (0.5 + 0.5 * _shimmerAnimation.value),
                                      ),
                                      blurRadius: 70 * _glowAnimation.value,
                                      spreadRadius: 24 * _glowAnimation.value,
                                    ),
                                  ],
                                ),
                              ),
                            // Logo image (transparent background)
                            SizedBox(
                              width: 260,
                              height: 260,
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 260,
                                height: 260,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.shield_rounded,
                                    size: 88,
                                    color: Colors.white,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              // Animated App Name with staggered animation
              FadeTransition(
                opacity: _textFade,
                child: SlideTransition(
                  position: _textSlide,
                  child: Column(
                    children: [
                      // Main title with gradient text effect
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.text,
                            AppColors.primary,
                            AppColors.text,
                          ],
                          stops: [
                            0.0,
                            0.5 + 0.3 * _shimmerAnimation.value,
                            1.0,
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'SENTINEL',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Tagline with fade in
                      AnimatedBuilder(
                        animation: _mainController,
                        builder: (context, child) {
                          final taglineOpacity = ((_mainController.value - 0.7) / 0.3).clamp(0.0, 1.0);
                          return Opacity(
                            opacity: taglineOpacity,
                            child: Column(
                              children: [
                                Text(
                                  'Society Management',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.text2,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'प्रहरी',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: AppColors.primary.withOpacity(0.8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
