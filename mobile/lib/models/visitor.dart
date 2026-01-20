class Visitor {
  final String visitorId;
  final String societyId;
  final String flatId;
  final String visitorType;
  final String visitorPhone;
  final String status;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String guardId;

  // Optional (future-proof)
  final String? photoPath;
  final String? photoUrl;
  final String? note;

  Visitor({
    required this.visitorId,
    required this.societyId,
    required this.flatId,
    required this.visitorType,
    required this.visitorPhone,
    required this.status,
    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
    required this.guardId,
    this.photoPath,
    this.photoUrl,
    this.note,
  });

  factory Visitor.fromJson(Map<String, dynamic> json) {
    return Visitor(
      visitorId: (json['visitor_id'] ?? '') as String,
      societyId: (json['society_id'] ?? '') as String,
      flatId: (json['flat_id'] ?? '') as String,
      visitorType: (json['visitor_type'] ?? '') as String,
      visitorPhone: (json['visitor_phone'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      approvedAt: json['approved_at'] != null && (json['approved_at'] as String).isNotEmpty
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      guardId: (json['guard_id'] ?? '') as String,
      photoPath: json['photo_path'] as String?,
      photoUrl: json['photo_url'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'visitor_id': visitorId,
      'society_id': societyId,
      'flat_id': flatId,
      'visitor_type': visitorType,
      'visitor_phone': visitorPhone,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by': approvedBy,
      'guard_id': guardId,
      'photo_path': photoPath,
      'photo_url': photoUrl,
      'note': note,
    };
  }
}
