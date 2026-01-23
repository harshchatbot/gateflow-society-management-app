import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/invite_utils.dart';

class BulkInviteUploadResult {
  final int processed;
  final int created;
  final int skipped;
  final List<String> errors;

  BulkInviteUploadResult({
    required this.processed,
    required this.created,
    required this.skipped,
    required this.errors,
  });
}

class InviteBulkUploadService {
  InviteBulkUploadService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<BulkInviteUploadResult> pickCsvAndUploadInvites({
    required String societyId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (pick == null || pick.files.isEmpty) {
      return BulkInviteUploadResult(
        processed: 0,
        created: 0,
        skipped: 0,
        errors: ["No file selected"],
      );
    }

    final file = pick.files.first;
    final bytes = file.bytes;
    if (bytes == null) throw Exception("Could not read CSV bytes");

    final csvText = utf8.decode(bytes);
    return uploadInvitesFromCsvText(
      societyId: societyId,
      csvText: csvText,
    );
  }

  Future<BulkInviteUploadResult> uploadInvitesFromCsvText({
    required String societyId,
    required String csvText,
  }) async {
    final createdByUid = _auth.currentUser?.uid;

    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvText);

    if (rows.isEmpty) {
      return BulkInviteUploadResult(
        processed: 0,
        created: 0,
        skipped: 0,
        errors: ["CSV empty"],
      );
    }

    final headerRow =
        rows.first.map((e) => e.toString().trim().toLowerCase()).toList();

    int idxEmail = headerRow.indexOf('email');
    int idxSystemRole = headerRow.indexOf('systemrole');
    int idxSocietyRole = headerRow.indexOf('societyrole');
    int idxFlatNo = headerRow.indexOf('flatno');

    final hasHeader = idxEmail != -1;
    if (!hasHeader) {
      idxEmail = 0;
      idxSystemRole = 1;
      idxSocietyRole = 2;
      idxFlatNo = 3;
    }

    final startIndex = hasHeader ? 1 : 0;

    int processed = 0;
    int created = 0;
    int skipped = 0;
    final errors = <String>[];

    WriteBatch batch = _db.batch();
    int ops = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (ops == 0) return;
      if (force || ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }

    for (int i = startIndex; i < rows.length; i++) {
      processed++;

      final row = rows[i].map((e) => e.toString().trim()).toList();

      String email = (idxEmail < row.length) ? row[idxEmail] : '';
      String systemRole =
          (idxSystemRole < row.length) ? row[idxSystemRole] : '';
      String societyRole =
          (idxSocietyRole < row.length) ? row[idxSocietyRole] : '';
      String flatNo = (idxFlatNo < row.length) ? row[idxFlatNo] : '';

      email = normalizeEmail(email);
      systemRole = systemRole.trim().toLowerCase();
      societyRole = societyRole.trim().toLowerCase();
      flatNo = flatNo.trim();

      if (email.isEmpty || !email.contains('@')) {
        skipped++;
        errors.add("Row $i: invalid email '$email'");
        continue;
      }

      if (systemRole != 'guard' && systemRole != 'resident') {
        skipped++;
        errors.add("Row $i: invalid systemRole '$systemRole'");
        continue;
      }

      if (systemRole == 'guard') {
        flatNo = '';
      }

      final inviteKey = inviteKeyFromEmail(email);

      final inviteRef = _db
          .collection('societies')
          .doc(societyId)
          .collection('invites')
          .doc(inviteKey);

      batch.set(inviteRef, {
        'email': email,
        'systemRole': systemRole,
        'societyRole': societyRole.isEmpty ? null : societyRole,
        'flatNo': flatNo.isEmpty ? null : flatNo,
        'status': 'pending',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': createdByUid,
      }, SetOptions(merge: true));

      ops++;
      created++;

      await commitIfNeeded();
    }

    await commitIfNeeded(force: true);

    return BulkInviteUploadResult(
      processed: processed,
      created: created,
      skipped: skipped,
      errors: errors,
    );
  }
}
