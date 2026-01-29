import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ui/app_loader.dart';
import 'join_society_screen.dart';
import 'guard_shell_screen.dart';
// TODO: resident shell later

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
      // You already have login screen routing
      return;
    }

    final db = FirebaseFirestore.instance;
    final pointerSnap = await db.collection('members').doc(user.uid).get();

    if (!mounted) return;

    if (!pointerSnap.exists) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const JoinSocietyScreen()),
      );
      return;
    }

    final data = pointerSnap.data() ?? {};
    final societyId = data['societyId']?.toString();
    final systemRole = data['systemRole']?.toString();

    if (societyId == null || societyId.isEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const JoinSocietyScreen()),
      );
      return;
    }

    if (systemRole == 'guard') {
      // fetch member name optionally
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
            societyId: societyId,
          ),
        ),
      );
      return;
    }

    // TODO: resident route
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const JoinSocietyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AppLoader.fullscreen(show: true),
    );
  }
}
