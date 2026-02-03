import 'package:flutter/material.dart';

import '../ui/sentinel_theme.dart';

class StatusChip extends StatelessWidget {
  /// Backward compatible:
  /// - Some screens use StatusChip(label: "APPROVED")
  /// - Others use StatusChip(status: "APPROVED")
  final String? label;
  final String? status;

  final bool compact;

  const StatusChip({
    super.key,
    this.label,
    this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final raw = (status ?? label ?? "").trim();
    final s = raw.toUpperCase();

    final chipBg = _bgColor(context, s);
    final chipFg = _textColor(context, s);
    final text = _label(s);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _borderColor(context, s)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: chipFg,
        ),
      ),
    );
  }

  String _label(String s) {
    switch (s) {
      case "APPROVED":
        return "APPROVED";
      case "REJECTED":
        return "REJECTED";
      case "PENDING":
        return "PENDING";
      case "LEAVE_AT_GATE":
        return "LEAVE AT GATE";
      default:
        return s.isEmpty ? "STATUS" : s;
    }
  }

  Color _bgColor(BuildContext context, String s) {
    switch (s) {
      case "APPROVED":
        return SentinelStatusPalette.bg(SentinelStatusPalette.success);
      case "REJECTED":
        return SentinelStatusPalette.bg(SentinelStatusPalette.error);
      case "PENDING":
        return SentinelStatusPalette.bg(SentinelStatusPalette.warning);
      case "LEAVE_AT_GATE":
        return SentinelStatusPalette.bg(SentinelStatusPalette.info);
      default:
        return Theme.of(context).colorScheme.onSurface.withOpacity(0.12);
    }
  }

  Color _borderColor(BuildContext context, String s) {
    switch (s) {
      case "APPROVED":
        return SentinelStatusPalette.border(SentinelStatusPalette.success);
      case "REJECTED":
        return SentinelStatusPalette.border(SentinelStatusPalette.error);
      case "PENDING":
        return SentinelStatusPalette.border(SentinelStatusPalette.warning);
      case "LEAVE_AT_GATE":
        return SentinelStatusPalette.border(SentinelStatusPalette.info);
      default:
        return Theme.of(context).colorScheme.onSurface.withOpacity(0.18);
    }
  }

  Color _textColor(BuildContext context, String s) {
    switch (s) {
      case "APPROVED":
        return SentinelStatusPalette.fg(SentinelStatusPalette.success);
      case "REJECTED":
        return SentinelStatusPalette.fg(SentinelStatusPalette.error);
      case "PENDING":
        return SentinelStatusPalette.fg(SentinelStatusPalette.warning);
      case "LEAVE_AT_GATE":
        return SentinelStatusPalette.fg(SentinelStatusPalette.info);
      default:
        return Theme.of(context).colorScheme.onSurface.withOpacity(0.85);
    }
  }
}
