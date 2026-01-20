class Guard {
  final String guardId;
  final String guardName;
  final String societyId;
  final String? token;

  Guard({
    required this.guardId,
    required this.guardName,
    required this.societyId,
    this.token,
  });

  factory Guard.fromJson(Map<String, dynamic> json) {
    return Guard(
      guardId: json['guard_id'] as String,
      guardName: json['guard_name'] as String,
      societyId: json['society_id'] as String,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guard_id': guardId,
      'guard_name': guardName,
      'society_id': societyId,
      'token': token,
    };
  }
}
