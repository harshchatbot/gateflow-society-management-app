import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/storage.dart';
import '../core/society_modules.dart';
import '../core/session_gate_service.dart';

import 'admin_pending_approval_screen.dart';
import 'admin_shell_screen.dart';
import 'find_society_screen.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'onboarding_welcome_screen.dart';
import 'resident_pending_approval_screen.dart';
import 'resident_shell_screen.dart';

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
      // ✅ load role hint early (prefs)
      await Storage.loadLastRoleHint();

      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser != null) {
        try {
          final gate = SessionGateService();
          final gateResult =
              await gate.validateSessionAfterLogin(firebaseUser.uid).timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => GateResult.blocked(
                      GateBlockReason.membershipNotFound,
                      'Unable to verify membership. Please try again.',
                    ),
                  );

          // ✅ If allowed + membership exists → route to correct shell/pending
          if (gateResult.allowed && gateResult.memberInfo != null && mounted) {
            final membership = gateResult.memberInfo!;
            final societyId = membership['societyId'] as String? ?? '';
            if (societyId.isNotEmpty) {
              await SocietyModules.ensureLoaded(societyId);
            }

            final systemRole = (membership['systemRole'] as String? ?? '')
                .trim()
                .toLowerCase();
            final name = membership['name'] as String? ?? '';
            final flatNo = membership['flatNo'] as String?;
            final societyRole = membership['societyRole'] as String?;
            final active = membership['active'] == true;

            if ((systemRole == 'admin' || systemRole == 'super_admin') &&
                societyId.isNotEmpty) {
              if (systemRole == 'admin' && !active) {
                targetScreen = AdminPendingApprovalScreen(
                  adminId: firebaseUser.uid,
                  societyId: societyId,
                  adminName: name.isNotEmpty ? name : "Admin",
                );
              } else {
                targetScreen = AdminShellScreen(
                  adminId: firebaseUser.uid,
                  adminName: name.isNotEmpty ? name : "Admin",
                  societyId: societyId,
                  role: (societyRole ?? 'ADMIN').toUpperCase(),
                  systemRole: systemRole,
                );
              }
            } else if (systemRole == 'guard' && societyId.isNotEmpty) {
              targetScreen = GuardShellScreen(
                guardId: firebaseUser.uid,
                guardName: name.isNotEmpty ? name : "Guard",
                societyId: societyId,
              );
            } else if (systemRole == 'resident' && societyId.isNotEmpty) {
              if (!active) {
                targetScreen = ResidentPendingApprovalScreen(
                  residentId: firebaseUser.uid,
                  societyId: societyId,
                  residentName: name.isNotEmpty ? name : "Resident",
                );
              } else if (flatNo != null && flatNo.isNotEmpty) {
                targetScreen = ResidentShellScreen(
                  residentId: firebaseUser.uid,
                  residentName: name.isNotEmpty ? name : "Resident",
                  societyId: societyId,
                  flatNo: flatNo,
                );
              }
            }
          }

          // ❌ If NOT allowed (membership missing/inactive/blocked) → handle onboarding routing
          if (targetScreen == null && !gateResult.allowed && mounted) {
            // If membership is missing, route by role hint ONLY.
            if (gateResult.blockReason == GateBlockReason.membershipNotFound) {
              final roleHint = (Storage.lastRoleHint ?? '').trim().toLowerCase();

              // ✅ If no role hint, always go to Choose Role (this fixes your issue)
              if (roleHint.isEmpty) {
                targetScreen = const OnboardingChooseRoleScreen();
              } else if (roleHint == 'admin') {
                final pendingSocietyId = await Storage.getAdminJoinSocietyId();
                if (pendingSocietyId != null) {
                  targetScreen = AdminPendingApprovalScreen(
                    adminId: firebaseUser.uid,
                    societyId: pendingSocietyId,
                    adminName: 'Admin',
                  );
                } else {
                  targetScreen = const FindSocietyScreen(mode: 'admin');
                }
              } else if (roleHint == 'resident') {
                final pendingSocietyId = await Storage.getResidentJoinSocietyId();
                if (pendingSocietyId != null) {
                  targetScreen = ResidentPendingApprovalScreen(
                    residentId: firebaseUser.uid,
                    societyId: pendingSocietyId,
                    residentName: 'Resident',
                  );
                } else {
                  targetScreen = const FindSocietyScreen(mode: 'resident');
                }
              } else if (roleHint == 'guard') {
                // For guard, never show FindSociety
                targetScreen = const OnboardingChooseRoleScreen();
              } else {
                targetScreen = const OnboardingChooseRoleScreen();
              }
            } else {
              // Other blocks (inactive society, etc.)
              try {
                await FirebaseAuth.instance.signOut();
                await Storage.clearAllSessions();
                await Storage.clearFirebaseSession();
                SocietyModules.clear();
                GateBlockMessage.set(
                  gateResult.userMessage ??
                      'Access blocked. Please contact your society admin.',
                );
              } catch (_) {}
              targetScreen = const OnboardingChooseRoleScreen();
            }
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
          targetScreen = const OnboardingChooseRoleScreen();
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
