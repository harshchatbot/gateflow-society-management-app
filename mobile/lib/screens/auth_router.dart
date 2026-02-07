import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/session_gate_service.dart';
import '../core/storage.dart';
import '../ui/app_loader.dart';

import 'admin_onboarding_screen.dart';
import 'admin_pending_approval_screen.dart';
import 'admin_shell_screen.dart';
import 'find_society_screen.dart';
import 'guard_join_screen.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'resident_pending_approval_screen.dart';
import 'resident_shell_screen.dart';

class AuthRouter extends StatefulWidget {
  const AuthRouter({super.key});

  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );
      return;
    }

    // ✅ Gate check (also returns memberInfo if available)
    final gate = SessionGateService();
    final gateResult = await gate.validateSessionAfterLogin(user.uid);

    if (!mounted) return;

    // ❌ Society inactive or blocked
    if (!gateResult.allowed) {
      await FirebaseAuth.instance.signOut();
      await Storage.clearAllSessions();
      await Storage.clearFirebaseSession();
      GateBlockMessage.set(
        gateResult.userMessage ??
            'This society is currently inactive. Please contact the society admin.',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );
      return;
    }

    // ✅ Membership (may be null if user has no pointer/membership yet)
    final membership = gateResult.memberInfo;

    // ✅ If membership doesn't exist, route based on roleHint (UI-only)
    if (membership == null) {
      final role = (Storage.lastRoleHint ?? '').toLowerCase();

      if (role == 'admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const AdminOnboardingScreen(defaultJoinMode: true),
          ),
        );
        return;
      }

      if (role == 'guard') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GuardJoinScreen()),
        );
        return;
      }

      // resident default
      if (role == 'resident') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FindSocietyScreen()),
        );
        return;
      }

      // No role hint? go back to choose role (never JoinSocietyScreen)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );
      return;
    }

    final societyId = membership['societyId']?.toString() ?? '';
    final systemRole = (membership['systemRole']?.toString() ?? '').toLowerCase();
    final name = membership['name']?.toString() ?? '';
    final flatNo = membership['flatNo']?.toString();
    final societyRole = membership['societyRole']?.toString();
    final active = membership['active'] == true;

    // ✅ If societyId is missing in membership, treat as "no membership" → onboarding by role hint
    if (societyId.isEmpty) {
      final role = (Storage.lastRoleHint ?? '').toLowerCase();

      if (role == 'admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const AdminOnboardingScreen(defaultJoinMode: true),
          ),
        );
        return;
      }
      if (role == 'guard') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GuardJoinScreen()),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FindSocietyScreen()),
      );
      return;
    }

    // ✅ Pending screens (admins/residents)
    if (systemRole == 'admin' && !active) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminPendingApprovalScreen(
            adminId: user.uid,
            societyId: societyId,
            adminName: name.isNotEmpty ? name : 'Admin',
          ),
        ),
      );
      return;
    }

    if (systemRole == 'resident' && !active) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResidentPendingApprovalScreen(
            residentId: user.uid,
            societyId: societyId,
            residentName: name.isNotEmpty ? name : 'Resident',
          ),
        ),
      );
      return;
    }

    // ✅ Shell routing
    if (systemRole == 'guard') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GuardShellScreen(
            guardId: user.uid,
            guardName: name.isNotEmpty ? name : 'Guard',
            societyId: societyId,
          ),
        ),
      );
      return;
    }

    if (systemRole == 'resident' && flatNo != null && flatNo.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResidentShellScreen(
            residentId: user.uid,
            residentName: name.isNotEmpty ? name : 'Resident',
            societyId: societyId,
            flatNo: flatNo,
          ),
        ),
      );
      return;
    }

    if (systemRole == 'admin' || systemRole == 'super_admin') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminShellScreen(
            adminId: user.uid,
            adminName: name.isNotEmpty ? name : 'Admin',
            societyId: societyId,
            role: (societyRole ?? 'ADMIN').toUpperCase(),
            systemRole: systemRole, // ✅ don't hardcode
          ),
        ),
      );
      return;
    }

    // ✅ Fallback: go to choose role (never JoinSocietyScreen)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppLoader.fullscreen(show: true),
    );
  }
}
