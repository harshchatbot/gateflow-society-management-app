import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'sentinel_alive_mascot.dart';

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

AliveMascotMood _aliveMoodFromSenti(SentiMood mood) {
  switch (mood) {
    case SentiMood.idle:
      return AliveMascotMood.idle;
    case SentiMood.alert:
      return AliveMascotMood.alert;
    case SentiMood.happy:
      return AliveMascotMood.happy;
    case SentiMood.warning:
      return AliveMascotMood.warning;
  }
}

/// Top hero section: greeting, status message, SENTI mascot.
/// Optional leading row (avatar + name) and trailing actions (e.g. bell, settings).
/// UI only; no backend logic.
class DashboardHero extends StatelessWidget {
  final String userName;
  final String statusMessage;
  final SentiMood mascotMood;
  final Widget? avatar;
  final Widget? trailingActions;

  /// Enable small delayed mascot nudge prompts (e.g. action suggestions).
  final bool enableMascotNudges;
  final List<String> mascotNudgeMessages;

  const DashboardHero({
    super.key,
    required this.userName,
    required this.statusMessage,
    this.mascotMood = SentiMood.idle,
    this.avatar,
    this.trailingActions,
    this.enableMascotNudges = false,
    this.mascotNudgeMessages = const <String>[],
  });

  @override
  Widget build(BuildContext context) {
    final greeting = dashboardGreeting();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (userName.isNotEmpty || trailingActions != null)
          const SizedBox(height: 20),
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
            _buildMascot(context),
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

  Widget _buildMascot(BuildContext context) {
    return SentinelAliveMascot(
      mood: _aliveMoodFromSenti(mascotMood),
      size: 120,
      showNudge: enableMascotNudges,
      nudgeMessages: mascotNudgeMessages,
      nudgeDelay: const Duration(seconds: 10),
      nudgeRotateEvery: const Duration(seconds: 7),
    ).animate().fadeIn(duration: 400.ms).scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1, 1),
          duration: 400.ms,
          curve: Curves.easeOut,
        );
  }
}
