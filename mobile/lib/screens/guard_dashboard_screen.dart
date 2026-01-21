import 'package:flutter/material.dart';

import '../ui/app_colors.dart';

class GuardDashboardScreen extends StatelessWidget {
  final String guardId;
  final String guardName;
  final String societyId;

  final int todayCount;
    final int pendingCount;
    final int approvedCount;

    final VoidCallback? onTapNewEntry;
    final VoidCallback? onTapVisitors;
    final VoidCallback? onTapDeliveries;
    final VoidCallback? onTapGatePass;


  const GuardDashboardScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,

    this.todayCount = 0,
    this.pendingCount = 0,
    this.approvedCount = 0,

    this.onTapNewEntry,
    this.onTapVisitors,
    this.onTapDeliveries,
    this.onTapGatePass,
  });



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Top “premium” gradient header
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 240,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.95),
                    AppColors.primary.withOpacity(0.75),
                    AppColors.primarySoft.withOpacity(0.45),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Welcome back,",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            guardName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _IconCircle(
                      icon: Icons.notifications_none_rounded,
                      onTap: () {}, // later
                    ),
                    const SizedBox(width: 10),
                    _IconCircle(
                      icon: Icons.settings_outlined,
                      onTap: () {}, // later
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Society Card
                _GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials(societyId),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Society",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              societyId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Guard ID: $guardId",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 28,
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Stats Row
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: "Today",
                        value: todayCount.toString(),
                        icon: Icons.today_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: "Pending",
                        value: pendingCount.toString(),
                        icon: Icons.hourglass_bottom_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: "Approved",
                        value: approvedCount.toString(),
                        icon: Icons.verified_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // Quick actions
                const Text(
                  "Quick Actions",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),

                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.05,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  children: [
                    _QuickAction(
                      label: "New Entry",
                      icon: Icons.person_add_alt_1_rounded,
                      tint: AppColors.primary,
                      onTap: () => onTapNewEntry?.call(),

                    ),
                    _QuickAction(
                      label: "Visitors",
                      icon: Icons.groups_2_outlined,
                      tint: AppColors.success,
                      onTap: () => onTapVisitors?.call(),
                    ),
                    _QuickAction(
                      label: "Deliveries",
                      icon: Icons.inventory_2_outlined,
                      tint: AppColors.warning,
                      onTap: () => onTapDeliveries?.call(),
                    ),
                    _QuickAction(
                      label: "Gate Pass",
                      icon: Icons.qr_code_2_rounded,
                      tint: AppColors.primary,
                      onTap: () => onTapGatePass?.call(),
                    ),
                    _QuickAction(
                      label: "Vehicles",
                      icon: Icons.directions_car_outlined,
                      tint: AppColors.text2,
                      onTap: () {},
                    ),
                    _QuickAction(
                      label: "Notices",
                      icon: Icons.campaign_outlined,
                      tint: AppColors.text2,
                      onTap: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // Recent activity placeholder (you can hook from /today later)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Recent Activity",
                        style: TextStyle(
                          color: AppColors.text2,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onTapVisitors,
                      child: const Text("View All"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                _ActivityTile(
                  title: "Amazon Delivery",
                  subtitle: "Package arrived at gate",
                  badge: "Pending",
                  badgeColor: AppColors.warning,
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: 10),
                _ActivityTile(
                  title: "Vikram Kumar",
                  subtitle: "Guest • Pre-approved",
                  badge: "Approved",
                  badgeColor: AppColors.success,
                  icon: Icons.person_outline_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String s) {
    if (s.trim().isEmpty) return "SR";
    final parts = s.split(RegExp(r'[^A-Za-z0-9]+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return "SR";
    if (parts.length == 1) return parts.first.substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/* ---------------- UI components ---------------- */

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconCircle({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: child,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.text2, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: tint, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
              textAlign: TextAlign.center,
            ),
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

  const _ActivityTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: badgeColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: badgeColor.withOpacity(0.22)),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
