import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/invite_utils.dart';

class InviteClaimResult {
  final bool claimed;
  final String? societyId;
  final String? systemRole;

  InviteClaimResult({
    required this.claimed,
    this.societyId,
    this.systemRole,
  });
}

class InviteClaimService {
  InviteClaimService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  /// Preferred approach: you already know societyId (from code / selection).
  /// Reads invite doc directly using inviteKey(email) => avoids query pitfalls.
  Future<InviteClaimResult> claimInviteForSociety({
    required String societyId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");

    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      throw Exception("User has no email");
    }

    final emailNorm = normalizeEmail(email);
    final inviteKey = inviteKeyFromEmail(emailNorm);

    final inviteRef = _db
        .collection('societies')
        .doc(societyId)
        .collection('invites')
        .doc(inviteKey);

    final inviteSnap = await inviteRef.get();
    if (!inviteSnap.exists) {
      return InviteClaimResult(claimed: false);
    }

    final invite = inviteSnap.data()!;
    final status = (invite['status'] ?? '').toString();
    final active = invite['active'] == true;
    final inviteEmail = (invite['email'] ?? '').toString().trim().toLowerCase();

    if (!active || status != 'pending' || inviteEmail != emailNorm) {
      return InviteClaimResult(claimed: false);
    }

    final systemRole = (invite['systemRole'] ?? '').toString(); // guard/resident
    final societyRole = invite['societyRole']; // nullable
    final flatNo = invite['flatNo']; // nullable

    final uid = user.uid;
    final now = FieldValue.serverTimestamp();

    final memberRef = _db
        .collection('societies')
        .doc(societyId)
        .collection('members')
        .doc(uid);

    final rootPointerRef = _db.collection('members').doc(uid);

    final batch = _db.batch();

    // 1) Create society member doc (self)
    batch.set(memberRef, {
      'uid': uid,
      'email': emailNorm,
      'systemRole': systemRole,
      'societyRole': societyRole,
      'flatNo': flatNo,
      'active': true,
      'createdAt': now,
    });

    // 2) Create / update root pointer
    batch.set(rootPointerRef, {
      'uid': uid,
      'societyId': societyId,
      'systemRole': systemRole,
      'active': true,
      'updatedAt': now,
    });

    // 3) Mark invite claimed
    batch.update(inviteRef, {
      'status': 'claimed',
      'claimedByUid': uid,
      'claimedAt': now,
    });

    await batch.commit();

    return InviteClaimResult(
      claimed: true,
      societyId: societyId,
      systemRole: systemRole,
    );
  }

    /// Auto-claim across societies (no societyId needed).
  /// Uses collectionGroup('invites') and finds email match.
  Future<InviteClaimResult> claimInviteAuto() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");

    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      throw Exception("User has no email");
    }

    final emailNorm = normalizeEmail(email);

    final qs = await _db
        .collectionGroup('invites')
        .where('email', isEqualTo: emailNorm)
        .where('active', isEqualTo: true)
        .where('status', isEqualTo: 'pending')
        .limit(5)
        .get();

    if (qs.docs.isEmpty) {
      return InviteClaimResult(claimed: false);
    }

    final doc = qs.docs.first;
    final data = doc.data();

    final inviteEmail = (data['email'] ?? '').toString().trim().toLowerCase();
    if (inviteEmail != emailNorm) {
      return InviteClaimResult(claimed: false);
    }

    // Path: societies/{societyId}/invites/{inviteKey}
    final segments = doc.reference.path.split('/');
    if (segments.length < 2) {
      throw Exception("Invalid invite path: ${doc.reference.path}");
    }

    final societyId = segments[1];
    if (societyId.trim().isEmpty) {
      throw Exception("Unable to detect societyId from invite path");
    }

    return await claimInviteForSociety(societyId: societyId);
  }



}
