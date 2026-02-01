import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/storage.dart';
import '../core/society_modules.dart';
import '../core/session_gate_service.dart';
import 'onboarding_welcome_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'guard_shell_screen.dart';
import 'resident_shell_screen.dart';
import 'admin_shell_screen.dart';

/// App entry: starts with the welcome (namaste) screen and runs session check.
/// If user is already logged in, replaces with the appropriate shell; otherwise stays on welcome.
class AppBootstrapScreen extends StatefulWidget {
  const AppBootstrapScreen({super.key});

  @override
  State<AppBootstrapScreen> createState() => _AppBootstrapScreenState();
}

class _AppBootstrapScreenState extends State<AppBootstrapScreen> {
  @override
  void initState() {
    super.initState();
    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    if (!mounted) return;

    Widget? targetScreen;

    try {
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
            targetScreen = const OnboardingChooseRoleScreen();
          }
        } catch (e, stackTrace) {
          if (kDebugMode) {
            debugPrint("Error in bootstrap gate: $e");
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
              guardName: guardSession.guardName.isNotEmpty ? guardSession.guardName : "Guard",
              societyId: guardSession.societyId.isNotEmpty ? guardSession.societyId : "Society",
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
            debugPrint("Error loading session: $e");
          }
        }
      }

      if (targetScreen != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => targetScreen!),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("Critical error in bootstrap: $e");
        debugPrint("Stack trace: $stackTrace");
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingWelcomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const OnboardingWelcomeScreen();
  }
}
