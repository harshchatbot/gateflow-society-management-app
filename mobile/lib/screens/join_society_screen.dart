import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ui/app_loader.dart';
import '../services/invite_claim_service.dart';
import 'guard_shell_screen.dart';
// TODO: import resident shell when ready

class JoinSocietyScreen extends StatefulWidget {
  const JoinSocietyScreen({super.key});

  @override
  State<JoinSocietyScreen> createState() => _JoinSocietyScreenState();
}

class _JoinSocietyScreenState extends State<JoinSocietyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Please login first");

      final code = _codeCtrl.text.trim();
      if (code.isEmpty) throw Exception("Enter society code");

      final db = FirebaseFirestore.instance;

      // 1) Resolve societyId from societyCodes/{code}
      final codeRef = db.collection('societyCodes').doc(code);
      final codeSnap = await codeRef.get();

      if (!codeSnap.exists) {
        throw Exception("Invalid society code");
      }

      final codeData = codeSnap.data() ?? {};
      final active = codeData['active'] == true;
      final societyId = codeData['societyId']?.toString();

      if (!active || societyId == null || societyId.isEmpty) {
        throw Exception("Society code inactive");
      }

      // 2) Claim invite (batch: member + pointer + invite update)
      final claimService = InviteClaimService();
      final result =
          await claimService.claimInviteForSociety(societyId: societyId);

      if (!result.claimed) {
        throw Exception(
          "No pending invite found for ${user.email}. Please contact admin.",
        );
      }

      // 3) Route based on role
      if (!mounted) return;

      if (result.systemRole == 'guard') {
        // Optional: fetch display name from member doc if you store it later
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
              societyId: societyId,
            ),
          ),
        );
        return;
      }

      // TODO: ResidentShellScreen route later
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Joined as ${result.systemRole}. UI not yet wired.")),
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
      appBar: AppBar(title: const Text("Join Society")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: "Society Code",
                hintText: "e.g. AJM123",
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _join,
                child: _loading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: AppLoader.inline(size: 20),
                      )
                    : const Text("Join"),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              )
            ]
          ],
        ),
      ),
    );
  }
}
