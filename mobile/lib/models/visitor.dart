class Visitor {
  final String visitorId;
  final String societyId;

  /// Backend/internal identifier (keep it)
  final String flatId;

  /// Guard-facing flat number (A-101) — NEW
  final String flatNo;

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

  /// Resident (flat owner) phone — so guard can call while approval is pending
  final String? residentPhone;

  /// New entry fields (walk-in)
  final String? visitorName;
  final String? deliveryPartner;
  final String? deliveryPartnerOther;
  final String? vehicleNumber;
  final String? entryMode;

  Visitor({
    required this.visitorId,
    required this.societyId,
    required this.flatId,
    required this.flatNo,
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
    this.residentPhone,
    this.visitorName,
    this.deliveryPartner,
    this.deliveryPartnerOther,
    this.vehicleNumber,
    this.entryMode,
  });

  factory Visitor.fromJson(Map<String, dynamic> json) {
    final createdAtStr = (json['created_at'] ?? '').toString();

    return Visitor(
      visitorId: (json['visitor_id'] ?? '') as String,
      societyId: (json['society_id'] ?? '') as String,
      flatId: (json['flat_id'] ?? '') as String,

      // NEW: parse flat_no safely
      flatNo: (json['flat_no'] ?? '') as String,

      visitorType: (json['visitor_type'] ?? '') as String,
      visitorPhone: (json['visitor_phone'] ?? '') as String,
      status: (json['status'] ?? '') as String,

      // safer parse to avoid crash if empty
      createdAt: createdAtStr.isNotEmpty
          ? DateTime.parse(createdAtStr)
          : DateTime.fromMillisecondsSinceEpoch(0),

      approvedAt: json['approved_at'] != null &&
              (json['approved_at'] as String).isNotEmpty
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      guardId: (json['guard_id'] ?? '') as String,
      photoPath: json['photo_path'] as String?,
      photoUrl: json['photo_url'] as String?,
      note: json['note'] as String?,
      residentPhone: (json['resident_phone'] ?? json['residentPhone']) as String?,
      visitorName: (json['visitor_name'] ?? json['visitorName']) as String?,
      deliveryPartner: (json['delivery_partner'] ?? json['deliveryPartner']) as String?,
      deliveryPartnerOther: (json['delivery_partner_other'] ?? json['deliveryPartnerOther']) as String?,
      vehicleNumber: (json['vehicle_number'] ?? json['vehicleNumber']) as String?,
      entryMode: (json['entry_mode'] ?? json['entryMode']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'visitor_id': visitorId,
      'society_id': societyId,
      'flat_id': flatId,

      // NEW
      'flat_no': flatNo,

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
      'resident_phone': residentPhone,
      'visitor_name': visitorName,
      'delivery_partner': deliveryPartner,
      'delivery_partner_other': deliveryPartnerOther,
      'vehicle_number': vehicleNumber,
      'entry_mode': entryMode,
    };
  }
}
