import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/admin_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';

/// Admin Dashboard Screen
/// 
/// Overview screen for admins showing key metrics and quick actions
/// Theme: Purple/Admin theme
class AdminDashboardScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;

  const AdminDashboardScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminService _service = AdminService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );

  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getStats(societyId: widget.societyId);

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _stats = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Admin dashboard stats loaded", data: _stats);
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load stats";
        });
        AppLogger.w("Failed to load admin stats: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading admin stats", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background Gradient Header (purple theme)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.admin, Color(0xFF7C3AED)], // Purple gradient
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _loadStats,
            color: AppColors.admin, // Purple refresh indicator
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),

                  // Stats Grid
                  if (_stats != null) _buildStatsGrid(),

                  const SizedBox(height: 25),
                  const Text("Quick Actions", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildActionGrid(),
                ],
              ),
            ),
          ),

          if (_isLoading) GlassLoader(show: true, message: "Loading Stats..."),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Welcome back,", style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600, fontSize: 14)),
              Text(widget.adminName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded, color: Colors.white),
          onPressed: () {
            // TODO: Admin settings
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Admin settings coming soon!"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
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
            width: 50, height: 50,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.business_rounded, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.societyId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const Text("Admin Portal Active", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = _stats!;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          label: "Residents",
          value: (stats['total_residents'] ?? 0).toString(),
          icon: Icons.people_rounded,
          color: AppColors.admin,
        ),
        _StatCard(
          label: "Guards",
          value: (stats['total_guards'] ?? 0).toString(),
          icon: Icons.shield_rounded,
          color: AppColors.primary,
        ),
        _StatCard(
          label: "Flats",
          value: (stats['total_flats'] ?? 0).toString(),
          icon: Icons.home_rounded,
          color: AppColors.success,
        ),
        _StatCard(
          label: "Visitors Today",
          value: (stats['visitors_today'] ?? 0).toString(),
          icon: Icons.person_add_rounded,
          color: AppColors.warning,
        ),
        _StatCard(
          label: "Pending",
          value: (stats['pending_approvals'] ?? 0).toString(),
          icon: Icons.hourglass_empty,
          color: AppColors.warning,
        ),
        _StatCard(
          label: "Approved Today",
          value: (stats['approved_today'] ?? 0).toString(),
          icon: Icons.verified_user_outlined,
          color: AppColors.success,
        ),
      ],
    );
  }

  Widget _buildActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _ActionItem(
          icon: Icons.people_rounded,
          title: "Manage Residents",
          subtitle: "View & manage residents",
          color: AppColors.admin,
          onTap: () {
            // TODO: Navigate to manage residents
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Manage Residents coming soon!"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
        _ActionItem(
          icon: Icons.shield_rounded,
          title: "Manage Guards",
          subtitle: "View & manage guards",
          color: AppColors.primary,
          onTap: () {
            // TODO: Navigate to manage guards
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Manage Guards coming soon!"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
        _ActionItem(
          icon: Icons.home_rounded,
          title: "Manage Flats",
          subtitle: "View & manage flats",
          color: AppColors.success,
          onTap: () {
            // TODO: Navigate to manage flats
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Manage Flats coming soon!"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
        _ActionItem(
          icon: Icons.history_rounded,
          title: "Visitor Logs",
          subtitle: "View all visitor entries",
          color: AppColors.warning,
          onTap: () {
            // TODO: Navigate to visitor logs
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Visitor Logs coming soon!"),
                backgroundColor: AppColors.admin,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
      ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 20)),
          Text(label, style: const TextStyle(color: AppColors.text2, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
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
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
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
    );
  }
}
