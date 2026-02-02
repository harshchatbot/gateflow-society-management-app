import 'package:flutter/material.dart';
import '../ui/sentinel_theme.dart';

/// Placeholder for future Duolingo-inspired characters/animations.
/// Use [kind] to identify the illustration slot (e.g. 'login', 'empty_state').
class SentinelIllustration extends StatelessWidget {
  final String kind;

  const SentinelIllustration({
    super.key,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: SentinelColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SentinelColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_rounded,
            size: 48,
            color: SentinelColors.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Illustration: $kind',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SentinelColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
