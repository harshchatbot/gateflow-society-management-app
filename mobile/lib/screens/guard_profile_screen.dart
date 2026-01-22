import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import 'role_select_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;

  const ProfileScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isOnDuty = true; // Duty Status Toggle

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // Premium Profile Header
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF1E40AF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    const CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.guardName,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      "Guard ID: ${widget.guardId}",
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 1. Duty Status & Shift Card
                  _buildDutyCard(),
                  const SizedBox(height: 20),

                  // 2. Performance Stats (Leaderboard Style)
                  _buildPerformanceStats(),
                  const SizedBox(height: 25),

                  // 3. Operational Tasks Grid
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("My Operations", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  _buildTaskGrid(),

                  const SizedBox(height: 30),

                  // 4. Logout Button
                  _buildLogoutButton(context),

                  const SizedBox(height: 120), // Nav Bar Spacer
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDutyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Duty Status", style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(_isOnDuty ? "Currently ON-DUTY" : "OFF-DUTY", 
                style: TextStyle(color: _isOnDuty ? AppColors.success : AppColors.error, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          Switch.adaptive(
            value: _isOnDuty,
            activeColor: AppColors.success,
            onChanged: (v) => setState(() => _isOnDuty = v),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceStats() {
    return Row(
      children: [
        _buildStatBox("4.8 ★", "Rating", Colors.orange),
        const SizedBox(width: 12),
        _buildStatBox("128", "Points", AppColors.primary),
        const SizedBox(width: 12),
        _buildStatBox("12h", "Shift", Colors.purple),
      ],
    );
  }

  Widget _buildStatBox(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
            Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildTaskItem(Icons.qr_code_scanner_rounded, "Patrolling", "Next: 04:00 PM"),
        _buildTaskItem(Icons.language_rounded, "Language", "English"),
        _buildTaskItem(Icons.support_agent_rounded, "Helpdesk", "2 New Tasks"),
        _buildTaskItem(Icons.info_outline_rounded, "Society Info", widget.societyId),
      ],
    );
  }

  Widget _buildTaskItem(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: () async {
          await Storage.clearGuardSession();
          AppLogger.i("Guard session cleared - logout successful");
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
              (route) => false,
            );
          }
        },
        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
        label: const Text("END SESSION", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w900)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}