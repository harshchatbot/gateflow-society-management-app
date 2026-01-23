String normalizeEmail(String email) => email.trim().toLowerCase();

String inviteKeyFromEmail(String email) {
  final e = normalizeEmail(email);
  return Uri.encodeComponent(e); // safe Firestore docId
}
