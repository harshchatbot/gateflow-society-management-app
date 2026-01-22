import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../services/visitor_service.dart';
import '../ui/glass_loader.dart';
import '../core/storage.dart';          // Added missing import
import '../models/visitor.dart';      // Added missing import
import 'notice_board_screen.dart';

class GuardDashboardScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;
  final VoidCallback? onTapNewEntry;
  final VoidCallback? onTapVisitors;

  const GuardDashboardScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
    this.onTapNewEntry,
    this.onTapVisitors,
  });

  @override
  State<GuardDashboardScreen> createState() => _GuardDashboardScreenState();
}

class _GuardDashboardScreenState extends State<GuardDashboardScreen> {
  final VisitorService _service = VisitorService();
  
  String _dynamicName = "";
  int todayCount = 0;
  int pendingCount = 0;
  int approvedCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize with passed name, then fetch fresh data
    _dynamicName = widget.guardName; 
    _syncDashboard();
  }

  Future<void> _syncDashboard() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Parallel fetch: Profile + Today's Stats from your FastAPI Backend
      final results = await Future.wait([
        _service.getGuardProfile(widget.guardId),
        _service.getTodayVisitors(guardId: widget.guardId),
      ]);

      // Explicitly cast the results to avoid 'Object?' errors
      final profileRes = results[0] as Result<Map<String, dynamic>>;
      final visitorsRes = results[1] as Result<List<Visitor>>;

      if (mounted) {
        setState(() {
          _isLoading = false;
          
          // 1. Update Profile Name dynamically
          if (profileRes.isSuccess && profileRes.data != null) {
            _dynamicName = profileRes.data!['name'] ?? widget.guardName;
            
            // Sync to storage so Profile page updates too
            Storage.saveGuardSession(
              guardId: widget.guardId,
              guardName: _dynamicName,
              societyId: widget.societyId,
            );
          }
          
          // 2. Update Stats and filter by status
          if (visitorsRes.isSuccess && visitorsRes.data != null) {
            final List<Visitor> v = visitorsRes.data!;
            todayCount = v.length;
            
            // Case-insensitive status check
            pendingCount = v.where((x) => x.status.toUpperCase() == 'PENDING').length;
            approvedCount = v.where((x) => x.status.toUpperCase() == 'APPROVED').length;
          }
        });
      }
    } catch (e) {
      debugPrint("Dashboard Sync Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background Gradient Header
          Positioned(
            left: 0, right: 0, top: 0, height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, Color(0xFF1E40AF)],
                ),
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: _syncDashboard,
            color: AppColors.primary,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildPremiumSocietyCard(),
                  const SizedBox(height: 20),
                  
                  // Dynamic Stats Row
                  Row(
                    children: [
                      Expanded(child: _StatCard(label: "Today", value: todayCount.toString(), icon: Icons.today, color: AppColors.primary)),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(label: "Pending", value: pendingCount.toString(), icon: Icons.hourglass_empty, color: AppColors.warning)),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(label: "Approved", value: approvedCount.toString(), icon: Icons.verified_user_outlined, color: AppColors.success)),
                    ],
                  ),

                  const SizedBox(height: 25),
                  const Text("Quick Actions", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildActionGrid(),
                  
                  const SizedBox(height: 25),
                  _buildRecentActivitySection(),
                ],
              ),
            ),
          ),
          
          if (_isLoading) GlassLoader(show: true, message: "Syncing Data..."),
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
              Text(_dynamicName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
            ],
          ),
        ),
        // Notification Bell Icon
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded, color: Colors.white),
              onPressed: () {
                // Navigate to visitor list to see pending approvals
                if (widget.onTapVisitors != null) {
                  widget.onTapVisitors!();
                }
              },
            ),
            if (pendingCount > 0)
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
                    pendingCount > 9 ? "9+" : pendingCount.toString(),
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
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onPressed: () => _showSettingsSheet(context),
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
                const Text("Society Management Active", style: TextStyle(color: Colors.white70, fontSize: 12)),
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
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _QuickAction(label: "New Entry", icon: Icons.person_add_rounded, tint: AppColors.primary, onTap: widget.onTapNewEntry),
        _QuickAction(label: "Visitors", icon: Icons.groups_rounded, tint: AppColors.success, onTap: widget.onTapVisitors),
        _QuickAction(
          label: "Notices",
          icon: Icons.notifications_rounded,
          tint: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoticeBoardScreen(
                  societyId: widget.societyId,
                  themeColor: AppColors.primary,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Recent Activity", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16)),
            TextButton(onPressed: widget.onTapVisitors, child: const Text("View All")),
          ],
        ),
        const SizedBox(height: 10),
        const _ActivityTile(title: "Amazon Delivery", subtitle: "Package at Gate 1", badge: "Pending", badgeColor: AppColors.warning, icon: Icons.inventory_2_outlined),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Gate Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.notifications_active, color: AppColors.primary),
              title: const Text("Alert Sounds"),
              trailing: Switch.adaptive(value: true, onChanged: (v) {}),
            ),
          ],
        ),
      ),
    );
  }
}

// --- HELPER COMPONENTS ---

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label, style: const TextStyle(color: AppColors.text2, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;
  const _QuickAction({required this.label, required this.icon, required this.tint, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: tint, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  const _ActivityTile({required this.title, required this.subtitle, required this.badge, required this.badgeColor, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
            ]),
          ),
          Text(badge, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}