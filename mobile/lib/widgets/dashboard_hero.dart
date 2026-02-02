import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../ui/app_colors.dart';

/// Mascot mood for SENTI owl. Drives which asset is shown.
enum SentiMood {
  idle,
  alert,
  happy,
  warning,
}

/// Returns greeting based on time of day (Good Morning / Afternoon / Evening).
String dashboardGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good Morning';
  if (hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

String _mascotAsset(SentiMood mood) {
  switch (mood) {
    case SentiMood.idle:
      return 'assets/mascot/senti_idle.png';
    case SentiMood.alert:
      return 'assets/mascot/senti_alert.png';
    case SentiMood.happy:
      return 'assets/mascot/senti_happy.png';
    case SentiMood.warning:
      return 'assets/mascot/senti_warning.png';
  }
}

/// Top hero section: greeting, status message, SENTI mascot.
/// Optional leading row (avatar + name) and trailing actions (e.g. bell, settings).
/// UI only; no backend logic.
class DashboardHero extends StatelessWidget {
  final String userName;
  final String statusMessage;
  final SentiMood mascotMood;
  /// Optional: pass pre-built avatar (e.g. with CachedNetworkImage) to avoid dependency.
  final Widget? avatar;
  final Widget? trailingActions;

  const DashboardHero({
    super.key,
    required this.userName,
    required this.statusMessage,
    this.mascotMood = SentiMood.idle,
    this.avatar,
    this.trailingActions,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = dashboardGreeting();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: optional avatar + name + trailing (bell, settings)
        if (userName.isNotEmpty || trailingActions != null)
          Row(
            children: [
              if (userName.isNotEmpty) ...[
                _buildAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
              if (trailingActions != null) trailingActions!,
            ],
          ),
        if (userName.isNotEmpty || trailingActions != null) const SizedBox(height: 20),
        // Status + mascot row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusMessage,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildMascot(),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
      ),
      child: avatar ??
          const CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(Icons.person_rounded, color: Colors.white),
          ),
    );
  }

  Widget _buildMascot() {
    return Image.asset(
      _mascotAsset(mascotMood),
      width: 120,
      height: 120,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.pets_rounded, color: Colors.white, size: 48),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1), duration: 400.ms, curve: Curves.easeOut);
  }
}
