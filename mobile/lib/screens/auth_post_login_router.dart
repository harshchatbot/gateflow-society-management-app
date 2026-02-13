import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/session_gate_service.dart';
import '../ui/app_loader.dart';
import '../services/invite_claim_service.dart';
import '../services/firestore_service.dart';
import 'admin_pending_approval_screen.dart';
import 'admin_shell_screen.dart';
import 'platform_super_admin_console_screen.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'resident_pending_approval_screen.dart';
import 'resident_shell_screen.dart';

class AuthPostLoginRouter extends StatefulWidget {
  final String
      defaultSocietyId; // you must pass societyId you’re onboarding into

  const AuthPostLoginRouter({
    super.key,
    required this.defaultSocietyId,
  });

  @override
  State<AuthPostLoginRouter> createState() => _AuthPostLoginRouterState();
}

class _AuthPostLoginRouterState extends State<AuthPostLoginRouter> {
  final FirestoreService _firestore = FirestoreService();
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
        final pendingSocietyRequest = await _firestore
            .getPendingSocietyCreationRequestForUser(uid: user.uid);
        if (pendingSocietyRequest != null) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AdminPendingApprovalScreen(
                adminId: user.uid,
                societyId:
                    (pendingSocietyRequest['proposedSocietyId'] ?? 'pending')
                        .toString(),
                adminName: (pendingSocietyRequest['requesterName'] ?? 'Admin')
                    .toString(),
                email:
                    (pendingSocietyRequest['requesterPhone'] ?? '').toString(),
                title: "Society Setup Pending",
                badgeText: "Waiting for Sentinel verification",
                message: "Your request is under review by Sentinel team.",
              ),
            ),
          );
          return;
        }

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
        if (!mounted) return;
        GateBlockMessage.set(gateResult.userMessage ??
            'This society is currently inactive. Please contact the society admin.');
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

        if (!mounted) return;
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

      if (systemRole == 'super_admin') {
        final platform =
            await _firestore.getPlatformAdminProfile(uid: user.uid);
        final active = platform?['active'] == true;
        final role = (platform?['role'] ?? platform?['systemRole'] ?? '')
            .toString()
            .toLowerCase();
        if (!(active && role == 'super_admin')) {
          setState(() {
            _loading = false;
            _error = "Super admin account is inactive.";
          });
          return;
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PlatformSuperAdminConsoleScreen(
              adminName: (platform?['name'] ?? 'Platform Admin').toString(),
            ),
          ),
        );
        return;
      }

      if (systemRole == 'admin') {
        final memberSnap = await db
            .collection('societies')
            .doc(societyId)
            .collection('members')
            .doc(user.uid)
            .get();
        final member = memberSnap.data() ?? {};
        final active = member['active'] == true;
        final name = (member['name'] ?? 'Admin').toString();
        final role =
            (member['societyRole'] ?? 'ADMIN').toString().toUpperCase();

        if (systemRole == 'admin' && !active) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AdminPendingApprovalScreen(
                adminId: user.uid,
                societyId: societyId!,
                adminName: name,
              ),
            ),
          );
          return;
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminShellScreen(
              adminId: user.uid,
              adminName: name,
              societyId: societyId!,
              role: role,
              systemRole: 'admin',
            ),
          ),
        );
        return;
      }

      if (systemRole == 'resident') {
        final memberSnap = await db
            .collection('societies')
            .doc(societyId)
            .collection('members')
            .doc(user.uid)
            .get();
        final member = memberSnap.data() ?? {};
        final active = member['active'] == true;
        final name = (member['name'] ?? 'Resident').toString();
        final flatNo = (member['flatNo'] ?? '').toString();

        if (!active) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ResidentPendingApprovalScreen(
                residentId: user.uid,
                societyId: societyId!,
                residentName: name,
              ),
            ),
          );
          return;
        }

        if (flatNo.isNotEmpty) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ResidentShellScreen(
                residentId: user.uid,
                residentName: name,
                societyId: societyId!,
                flatNo: flatNo,
              ),
            ),
          );
          return;
        }
      }

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
