import 'package:flutter/material.dart';

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

    final bg = _bgColor(s);
    final fg = _textColor(s);
    final text = _label(s);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: fg,
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

  Color _bgColor(String s) {
    switch (s) {
      case "APPROVED":
        return Colors.green.withOpacity(0.12);
      case "REJECTED":
        return Colors.red.withOpacity(0.12);
      case "PENDING":
        return Colors.orange.withOpacity(0.14);
      case "LEAVE_AT_GATE":
        return Colors.blue.withOpacity(0.12);
      default:
        return Colors.grey.withOpacity(0.12);
    }
  }

  Color _textColor(String s) {
    switch (s) {
      case "APPROVED":
        return Colors.green.shade800;
      case "REJECTED":
        return Colors.red.shade700;
      case "PENDING":
        return Colors.orange.shade800;
      case "LEAVE_AT_GATE":
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade700;
    }
  }
}
