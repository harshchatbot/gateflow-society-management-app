import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/resident_service.dart';
import '../core/app_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Resident Dashboard Screen
/// 
/// Purpose: Overview screen for residents showing:
/// - Welcome message with resident info
/// - Quick stats (pending approvals count)
/// - Quick action cards to navigate to Approvals/History
/// 
/// Differences from Guard Dashboard:
/// - No visitor creation actions (guards only)
/// - No guard-specific stats
/// - Simpler layout focused on approvals
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
    baseUrl: dotenv.env["API_BASE_URL"] ?? "http://192.168.29.195:8000",
  );

  int _pendingCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await _service.getApprovals(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _pendingCount = result.data!.length;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_pendingCount} pending approvals");
      } else {
        setState(() => _isLoading = false);
        AppLogger.w("Failed to load approvals: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading pending count", error: e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background Gradient Header (similar to guard dashboard)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 200,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.8),
                    AppColors.primarySoft,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  _buildHeader(),
                  const SizedBox(height: 24),
                  
                  // Quick Stats Card
                  _buildStatsCard(),
                  const SizedBox(height: 20),
                  
                  // Quick Actions
                  _buildQuickActions(),
                ],
              ),
            ),
          ),
          GlassLoader(show: _isLoading, message: "Loading…"),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome back,",
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.residentName,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            "Flat ${widget.flatNo} • ${widget.societyId}",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.pending_actions_rounded,
              color: AppColors.warning,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Pending Approvals",
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$_pendingCount",
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Quick Actions",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 12),
        // Approvals Card
        _buildActionCard(
          icon: Icons.verified_rounded,
          title: "View Approvals",
          subtitle: "$_pendingCount pending requests",
          color: AppColors.warning,
          onTap: () {
            // Navigate to approvals tab (handled by shell)
            // This is a placeholder - shell will handle navigation
          },
        ),
        const SizedBox(height: 12),
        // History Card
        _buildActionCard(
          icon: Icons.history_rounded,
          title: "View History",
          subtitle: "Past approvals & rejections",
          color: AppColors.primary,
          onTap: () {
            // Navigate to history tab (handled by shell)
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.text2,
            ),
          ],
        ),
      ),
    );
  }
}
