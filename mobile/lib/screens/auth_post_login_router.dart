import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/session_gate_service.dart';
import '../ui/app_loader.dart';
import '../services/invite_claim_service.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';

class AuthPostLoginRouter extends StatefulWidget {
  final String defaultSocietyId; // you must pass societyId you’re onboarding into

  const AuthPostLoginRouter({
    super.key,
    required this.defaultSocietyId,
  });

  @override
  State<AuthPostLoginRouter> createState() => _AuthPostLoginRouterState();
}

class _AuthPostLoginRouterState extends State<AuthPostLoginRouter> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _error = "Not logged in";
        });
        return;
      }

      final db = FirebaseFirestore.instance;
      final rootPointerRef = db.collection('members').doc(user.uid);
      final rootSnap = await rootPointerRef.get();

      String? societyId;
      String? systemRole;

      if (rootSnap.exists) {
        final data = rootSnap.data()!;
        societyId = data['societyId']?.toString();
        systemRole = data['systemRole']?.toString();
      }

      // If no pointer, try to claim invite for the society you’re onboarding into
      if (societyId == null || societyId.isEmpty) {
        final claimService = InviteClaimService();
        final result = await claimService.claimInviteForSociety(
          societyId: widget.defaultSocietyId,
        );

        if (!result.claimed) {
          setState(() {
            _loading = false;
            _error = "No invite found for your email in this society.";
          });
          return;
        }

        societyId = result.societyId;
        systemRole = result.systemRole;
      }

      // Post-login gate: block if membership or society inactive
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

      // Route based on role
      if (!mounted) return;

      if (systemRole == 'guard') {
        // You already have guard shell args: guardId, guardName, societyId
        // We can fetch guard name from member doc (optional)
        final memberSnap = await db
            .collection('societies')
            .doc(societyId)
            .collection('members')
            .doc(user.uid)
            .get();

        final member = memberSnap.data() ?? {};
        final guardName = (member['name'] ?? 'Guard').toString();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GuardShellScreen(
              guardId: user.uid,
              guardName: guardName,
              societyId: societyId!,
            ),
          ),
        );
        return;
      }

      // TODO: route resident later
      setState(() {
        _loading = false;
        _error = "Logged in, but role '$systemRole' UI not implemented yet.";
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: AppLoader.fullscreen(show: true),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Sentinel")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error ?? "Unknown error"),
        ),
      ),
    );
  }
}
