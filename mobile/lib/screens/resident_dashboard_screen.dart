import 'dart:async';
import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/resident_service.dart' as resident;
import '../services/notification_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import 'resident_complaint_screen.dart';
import 'resident_approvals_screen.dart';
import 'notice_board_screen.dart';
import 'role_select_screen.dart';
import '../widgets/resident_notification_drawer.dart';
import '../services/firestore_service.dart';

/// Resident Dashboard Screen
///
/// Purpose: Overview screen for residents showing:
/// - Welcome message with resident info
/// - Quick stats (pending approvals count)
/// - Quick action cards to navigate to Approvals/History
///
/// Theme: Green/Success theme (matching resident login)
class ResidentDashboardScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;

  const ResidentDashboardScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentDashboardScreen> createState() => _ResidentDashboardScreenState();
}

class _ResidentDashboardScreenState extends State<ResidentDashboardScreen> {
  // 🔹 Firestore (new, for notices)
  final FirestoreService _firestore = FirestoreService();

  // 🔹 Existing backend service (leave untouched)
  late final resident.ResidentService _service = resident.ResidentService(
    baseUrl: Env.apiBaseUrl.isNotEmpty
        ? Env.apiBaseUrl
        : "http://192.168.29.195:8000",
  );

  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;
  int _notificationCount = 0; // Total notifications (approvals + notices)
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    // Listen for new notifications to update count
    final notificationService = NotificationService();
    notificationService.setOnNotificationReceived((data) {
      if (data['type'] == 'notice' || data['type'] == 'visitor') {
        _loadDashboardData(); // Refresh data when notification received
      }
    });
    notificationService.setOnNotificationTap((data) {
      final type = (data['type'] ?? '').toString();
      if (type == 'visitor') {
        // Open approvals screen/tab (handled via shell/tab; for now just refresh)
        _loadDashboardData();
      } else if (type == 'notice') {
        // Open notice board screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoticeBoardScreen(
              societyId: widget.societyId,
              themeColor: AppColors.success,
            ),
          ),
        );
      } else if (type == 'complaint') {
        // For complaints, open complaints tab/screen in future; for now just log
        AppLogger.i("Complaint notification tapped (resident)", data: data);
      }
    });
  }

  // ✅ Helper: Load notices from Firestore and return as List<Map<String,dynamic>>
  Future<List<Map<String, dynamic>>> _loadNoticesList() async {
    try {
      final raw = await _firestore.getNotices(
        societyId: widget.societyId,
        activeOnly: true,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.w("getNotices timeout");
          return <Map<String, dynamic>>[]; // Return correct type
        },
      );

      return raw.map<Map<String, dynamic>>((n) {
        return Map<String, dynamic>.from(n as Map);
      }).toList();
    } catch (e, st) {
      AppLogger.e("Error loading notices (Firestore)", error: e, stackTrace: st);
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Load pending approvals with timeout
      resident.ApiResult<List<dynamic>>? approvalsResult;
      try {
        approvalsResult = await _service
            .getApprovals(
              societyId: widget.societyId,
              flatNo: widget.flatNo,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                AppLogger.w("getApprovals timeout");
                return resident.ApiResult.failure("Request timeout");
              },
            );
      } catch (e) {
        AppLogger.e("Error loading approvals", error: e);
        approvalsResult = resident.ApiResult.failure("Failed to load approvals");
      }

      // Load history for stats with timeout
      resident.ApiResult<List<dynamic>>? historyResult;
      try {
        historyResult = await _service
            .getHistory(
              societyId: widget.societyId,
              flatNo: widget.flatNo,
              limit: 100,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                AppLogger.w("getHistory timeout");
                return resident.ApiResult.failure("Request timeout");
              },
            );
      } catch (e) {
        AppLogger.e("Error loading history", error: e);
        historyResult = resident.ApiResult.failure("Failed to load history");
      }

      if (!mounted) return;

      if (approvalsResult != null &&
          approvalsResult.isSuccess &&
          approvalsResult.data != null) {
        _pendingCount = approvalsResult.data!.length;
      }

      if (historyResult != null && historyResult.isSuccess && historyResult.data != null) {
        final history = historyResult.data!;
        _approvedCount = history.where((item) {
          final status = item['status']?.toString().toUpperCase() ?? '';
          return status == 'APPROVED';
        }).length;
        _rejectedCount = history.where((item) {
          final status = item['status']?.toString().toUpperCase() ?? '';
          return status == 'REJECTED';
        }).length;
      }

      // ✅ Count recent notices (created in last 24 hours) via Firestore list
      int recentNotices = 0;
      try {
        final noticesList = await _loadNoticesList();
        final now = DateTime.now();

        recentNotices = noticesList.where((n) {
          try {
            // Prefer 'created_at' if your notice docs use snake_case
            final createdAtStr = (n['created_at'] ?? n['createdAt'])?.toString() ?? '';
            if (createdAtStr.isEmpty) return false;

            // If stored as ISO string
            final created = DateTime.parse(createdAtStr.replaceAll("Z", "+00:00"));
            final hoursDiff = now.difference(created).inHours;
            return hoursDiff <= 24;
          } catch (_) {
            // If createdAt is Timestamp or invalid format, skip gracefully
            return false;
          }
        }).length;
      } catch (e) {
        AppLogger.e("Error counting notices", error: e);
        // Continue without notices count
      }

      // Total notification count = pending approvals + recent notices
      _notificationCount = _pendingCount + recentNotices;

      if (mounted) {
        setState(() => _isLoading = false);
      }

      AppLogger.i("Resident dashboard loaded", data: {
        "pending": _pendingCount,
        "approved": _approvedCount,
        "rejected": _rejectedCount,
        "notices": recentNotices,
      });
    } catch (e) {
      AppLogger.e("Error loading dashboard data", error: e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _onWillPop() async {
    // Show confirmation dialog when back is pressed on dashboard
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text('Do you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (shouldExit == true && context.mounted) {
      // Navigate to role select instead of just popping
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
        (route) => false,
      );
      return false; // Don't pop, we already navigated
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _onWillPop().then((shouldExit) {
              if (shouldExit && context.mounted) {
                Navigator.of(context).pop();
              }
            }),
          ),
        ),
        body: Stack(
        children: [
          // Green Gradient Header Background
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 260,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.success,
                    AppColors.success.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: AppColors.success,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),

                  // Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: "Pending",
                          value: _pendingCount.toString(),
                          icon: Icons.pending_actions_rounded,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: "Approved",
                          value: _approvedCount.toString(),
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: "Rejected",
                          value: _rejectedCount.toString(),
                          icon: Icons.cancel_rounded,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),
                  const Text(
                    "Quick Actions",
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildActionGrid(),
                ],
              ),
            ),
          ),

          if (_isLoading) GlassLoader(show: true, message: "Loading Dashboard…"),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.residentName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Notification Bell Icon
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded, color: Colors.white),
              onPressed: () {
                // Show notification drawer
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => ResidentNotificationDrawer(
                    societyId: widget.societyId,
                    residentId: widget.residentId,
                    flatNo: widget.flatNo,
                  ),
                ).then((_) {
                  // Refresh notification count when drawer closes
                  _loadDashboardData();
                });
              },
            ),
            if (_notificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    _notificationCount > 9 ? "9+" : _notificationCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPremiumSocietyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.apartment_rounded, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.societyId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Flat ${widget.flatNo}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildActionCard(
          icon: Icons.verified_user_rounded,
          title: "Pending Approvals",
          subtitle: "$_pendingCount requests",
          color: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ResidentApprovalsScreen(
                  residentId: widget.residentId,
                  societyId: widget.societyId,
                  flatNo: widget.flatNo,
                ),
              ),
            );
          },
        ),
        _buildActionCard(
          icon: Icons.report_problem_rounded,
          title: "Raise Complaint",
          subtitle: "Report an issue",
          color: AppColors.error,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ResidentComplaintScreen(
                  residentId: widget.residentId,
                  residentName: widget.residentName,
                  societyId: widget.societyId,
                  flatNo: widget.flatNo,
                ),
              ),
            );
          },
        ),
        _buildActionCard(
          icon: Icons.inbox_rounded,
          title: "My Complaints",
          subtitle: "View all complaints",
          color: AppColors.primary,
          onTap: () {
            // Navigate to complaints tab - handled by shell
            // For now, show snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Use the Complaints tab below to view your complaints"),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
        _buildActionCard(
          icon: Icons.history_rounded,
          title: "View History",
          subtitle: "Past decisions",
          color: AppColors.success,
          onTap: () {
            // Navigate to history tab - handled by shell
          },
        ),
        _buildActionCard(
          icon: Icons.notifications_rounded,
          title: "Notice Board",
          subtitle: "Society announcements",
          color: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoticeBoardScreen(
                  societyId: widget.societyId,
                  themeColor: AppColors.success,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.text2,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
