import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ui/app_loader.dart';
import '../services/invite_claim_service.dart';
import 'guard_shell_screen.dart';
// TODO: Add ResidentShellScreen later

class JoinAndSignupScreen extends StatefulWidget {
  const JoinAndSignupScreen({super.key});

  @override
  State<JoinAndSignupScreen> createState() => _JoinAndSignupScreenState();
}

class _JoinAndSignupScreenState extends State<JoinAndSignupScreen> {
  final _codeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<String> _resolveSocietyId(String code) async {
    final db = FirebaseFirestore.instance;
    final snap = await db.collection('societyCodes').doc(code).get();

    if (!snap.exists) {
      throw Exception("Invalid society code");
    }

    final data = snap.data() ?? {};
    if (data['active'] != true) {
      throw Exception("Society code inactive");
    }

    final societyId = data['societyId']?.toString();
    if (societyId == null || societyId.isEmpty) {
      throw Exception("SocietyId missing for this code");
    }
    return societyId;
  }

  Future<UserCredential> _loginOrSignup(String email, String pass) async {
    final auth = FirebaseAuth.instance;

    try {
      return await auth.signInWithEmailAndPassword(email: email, password: pass);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return await auth.createUserWithEmailAndPassword(email: email, password: pass);
      }
      rethrow;
    }
  }

  Future<void> _joinSignupAndClaim() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final code = _codeCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text;

      if (code.isEmpty) throw Exception("Enter society code");
      if (email.isEmpty) throw Exception("Enter email");
      if (pass.length < 6) throw Exception("Password must be at least 6 characters");

      // 1) Resolve societyId from code
      final societyId = await _resolveSocietyId(code);

      // 2) Login or Signup
      await _loginOrSignup(email, pass);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Auth failed");

      // 3) Claim invite (batch)
      final claimService = InviteClaimService();
      final result = await claimService.claimInviteForSociety(societyId: societyId);

      if (!result.claimed) {
        throw Exception("No pending invite found for ${user.email}. Please contact admin.");
      }

      if (!mounted) return;

      // 4) Route based on role
      if (result.systemRole == 'guard') {
        final db = FirebaseFirestore.instance;
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

      // Resident shell not yet wired
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Joined as ${result.systemRole}. Resident UI pending.")),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Join Sentinel")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text("Enter Society Code + Sign up/Login to join"),
            const SizedBox(height: 12),

            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: "Society Code",
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _joinSignupAndClaim(),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _joinSignupAndClaim,
                child: _loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: AppLoader.inline(size: 20),
                      )
                    : const Text("Join & Continue"),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
