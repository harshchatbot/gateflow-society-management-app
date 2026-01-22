import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/resident_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import 'resident_complaint_screen.dart';
import 'resident_shell_screen.dart';
import 'notice_board_screen.dart';

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
  late final ResidentService _service = ResidentService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );

  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Load pending approvals
      final approvalsResult = await _service.getApprovals(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
      );

      // Load history for stats
      final historyResult = await _service.getHistory(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        limit: 100,
      );

      if (!mounted) return;

      if (approvalsResult.isSuccess && approvalsResult.data != null) {
        _pendingCount = approvalsResult.data!.length;
      }

      if (historyResult.isSuccess && historyResult.data != null) {
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

      setState(() => _isLoading = false);
      AppLogger.i("Resident dashboard loaded", data: {
        "pending": _pendingCount,
        "approved": _approvedCount,
        "rejected": _rejectedCount,
      });
    } catch (e) {
      AppLogger.e("Error loading dashboard data", error: e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
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
                // Navigate to approvals tab
                // This will be handled by the shell screen
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _pendingCount > 0
                          ? "You have $_pendingCount pending approval${_pendingCount > 1 ? 's' : ''}"
                          : "No pending approvals",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
            if (_pendingCount > 0)
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
                    _pendingCount > 9 ? "9+" : _pendingCount.toString(),
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
            // Navigate to approvals tab - handled by shell
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
