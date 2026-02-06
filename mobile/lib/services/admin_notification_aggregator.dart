import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../services/complaint_service.dart';
import '../services/notice_service.dart';
import '../services/resident_signup_service.dart';
import '../core/society_modules.dart';

class AdminNotificationCounts {
  final int pendingSignups;
  final int pendingComplaints;
  final int recentNotices;
  final int openSos;

  int get total =>
      pendingSignups + pendingComplaints + recentNotices + openSos;

  const AdminNotificationCounts({
    required this.pendingSignups,
    required this.pendingComplaints,
    required this.recentNotices,
    required this.openSos,
  });
}

class AdminNotificationAggregator {
  static Future<AdminNotificationCounts> load({
    required String societyId,
    required FirestoreService firestore,
    required ComplaintService complaintService,
    required NoticeService noticeService,
    required ResidentSignupService signupService,
  }) async {
    int pendingSignups = 0;
    int pendingComplaints = 0;
    int recentNotices = 0;
    int openSos = 0;

    // Join requests
    final residents =
        await firestore.getResidentJoinRequestsForAdmin(societyId);
    final admins =
        await firestore.getAdminJoinRequestsForAdmin(societyId);
    pendingSignups += residents.length + admins.length;

    // Society-code signups
    final signups = await signupService.getPendingSignups(societyId: societyId);
    if (signups.isSuccess && signups.data != null) {
      pendingSignups += signups.data!.length;
    }

    // Complaints
    if (SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
      final complaints =
          await complaintService.getAllComplaints(societyId: societyId);
      if (complaints.isSuccess && complaints.data != null) {
        pendingComplaints = complaints.data!.where((c) {
          final status = (c['status'] ?? '').toString().toUpperCase();
          return status == 'PENDING' || status == 'IN_PROGRESS';
        }).length;
      }
    }

    // Notices (last 24h)
    if (SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      final notices =
          await noticeService.getNotices(societyId: societyId, activeOnly: true);
      if (notices.isSuccess && notices.data != null) {
        final now = DateTime.now();
        recentNotices = notices.data!.where((n) {
          try {
            final created =
                DateTime.parse(n['created_at'].replaceAll("Z", "+00:00"));
            return now.difference(created).inHours <= 24;
          } catch (_) {
            return false;
          }
        }).length;
      }
    }

    // SOS
    if (SocietyModules.isEnabled(SocietyModuleIds.sos)) {
      final sos = await firestore.getSosRequests(societyId: societyId);
      openSos = sos.where((s) {
        final status = (s['status'] ?? 'OPEN').toString().toUpperCase();
        return status == 'OPEN';
      }).length;
    }

    return AdminNotificationCounts(
      pendingSignups: pendingSignups,
      pendingComplaints: pendingComplaints,
      recentNotices: recentNotices,
      openSos: openSos,
    );
  }
}
