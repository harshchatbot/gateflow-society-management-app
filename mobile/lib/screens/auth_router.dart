import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/session_gate_service.dart';
import '../ui/app_loader.dart';
import 'join_society_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'guard_shell_screen.dart';
import 'resident_shell_screen.dart';
import 'admin_shell_screen.dart';

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
    if (user == null) return;

    final gate = SessionGateService();
    final gateResult = await gate.validateSessionAfterLogin(user.uid);

    if (!mounted) return;

    if (!gateResult.allowed) {
      await FirebaseAuth.instance.signOut();
      await Storage.clearAllSessions();
      await Storage.clearFirebaseSession();
      GateBlockMessage.set(gateResult.userMessage ?? 'This society is currently inactive. Please contact the society admin.');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );
      return;
    }

    final membership = gateResult.memberInfo!;
    final societyId = membership['societyId']?.toString() ?? '';
    final systemRole = membership['systemRole']?.toString() ?? '';
    final name = membership['name']?.toString() ?? '';
    final flatNo = membership['flatNo']?.toString();
    final societyRole = membership['societyRole']?.toString();

    if (societyId.isEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const JoinSocietyScreen()),
      );
      return;
    }

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
            role: (societyRole ?? 'ADMIN').toUpperCase(), systemRole: 'admin',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const JoinSocietyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppLoader.fullscreen(show: true),
    );
  }
}
