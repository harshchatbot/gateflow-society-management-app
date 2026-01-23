class Invite {
  final String email;
  final String systemRole; // guard/resident
  final String? societyRole;
  final String? flatNo;
  final String status; // pending/claimed
  final bool active;

  Invite({
    required this.email,
    required this.systemRole,
    required this.status,
    required this.active,
    this.societyRole,
    this.flatNo,
  });

  factory Invite.fromMap(Map<String, dynamic> data) {
    return Invite(
      email: (data['email'] ?? '').toString(),
      systemRole: (data['systemRole'] ?? '').toString(),
      societyRole: data['societyRole']?.toString(),
      flatNo: data['flatNo']?.toString(),
      status: (data['status'] ?? '').toString(),
      active: data['active'] == true,
    );
  }
}
