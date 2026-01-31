import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';

// New UI system (no logic changes)
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';

// ✅ Phosphor icon mapping (single source)
import '../ui/app_icons.dart';

class VisitorDetailsScreen extends StatefulWidget {
  final Visitor visitor;
  final String guardId;
  /// When false (e.g. opened by guard), Approve/Reject/Leave actions are hidden. Residents use their own approval screen.
  final bool showStatusActions;
  const VisitorDetailsScreen({
    super.key,
    required this.visitor,
    required this.guardId,
    this.showStatusActions = false,
  });

  @override
  State<VisitorDetailsScreen> createState() => _VisitorDetailsScreenState();
}

class _VisitorDetailsScreenState extends State<VisitorDetailsScreen> {
  final _service = VisitorService();
  bool _loading = false;
  String? _error;
  late Visitor _visitor;

  final _noteController = TextEditingController();
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _visitor = widget.visitor;
    _noteController.text = _visitor.note ?? "";
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _noteController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(String status) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _service.updateVisitorStatus(
      visitorId: _visitor.visitorId,
      status: status,
      approvedBy: "GUARD:${widget.guardId}", // later replace with resident
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _visitor = res.data!;
        // Play celebration only when entry is approved
        if (_visitor.status.toUpperCase().contains('APPROV')) {
          _confettiController.play();
        }
      } else {
        _error = res.error?.userMessage ?? "Failed to update status";
      }
    });
  }

  bool _isPending(String status) {
    final s = status.toUpperCase();
    return s == 'PENDING';
  }

  Color _statusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains("APPROV")) return AppColors.success;
    if (s.contains("REJECT")) return AppColors.error;
    if (s.contains("LEAVE")) return AppColors.warning;
    if (s.contains("PENDING")) return AppColors.text2;
    return AppColors.textMuted;
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final localTime = dateTime.toLocal();

    String dateStr;
    if (dateOnly == today) {
      dateStr = "Today";
    } else if (dateOnly == yesterday) {
      dateStr = "Yesterday";
    } else {
      dateStr = "${localTime.day}/${localTime.month}/${localTime.year}";
    }

    final timeStr = "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";
    return "$dateStr at $timeStr";
  }

  // ✅ Phosphor icons for visitor type
  IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case "DELIVERY":
        return AppIcons.delivery;
      case "CAB":
        return AppIcons.cab;
      case "GUEST":
        return AppIcons.guest;
      default:
        return AppIcons.visitor;
    }
  }

  // ✅ Optional: Phosphor icons for status chips
  IconData _statusIcon(String status) {
    final s = status.toUpperCase();
    if (s.contains("APPROV")) return AppIcons.approved;
    if (s.contains("REJECT")) return AppIcons.rejected;
    if (s.contains("LEAVE")) return AppIcons.leave;
    if (s.contains("PENDING")) return AppIcons.pending;
    return AppIcons.more;
  }

  Widget _photoHeader() {
    final hasPhoto = _visitor.photoUrl != null && _visitor.photoUrl!.isNotEmpty;

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              Image.network(
                _visitor.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.bg,
                  child: Center(
                    child: Icon(
                      AppIcons.more, // ✅ replaces image_not_supported
                      color: AppColors.textMuted.withOpacity(0.8),
                      size: 40,
                    ),
                  ),
                ),
              )
            else
              Container(
                color: AppColors.bg,
                child: Center(
                  child: Icon(
                    _typeIcon(_visitor.visitorType),
                    size: 58,
                    color: AppColors.primary,
                  ),
                ),
              ),

            // Subtle gradient overlay for readability
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.00),
                      Colors.black.withOpacity(0.28),
                    ],
                  ),
                ),
              ),
            ),

            // Status chip + type label overlay
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border.withOpacity(0.9)),
                    ),
                    child: Row(
                      children: [
                        Icon(_typeIcon(_visitor.visitorType), size: 16, color: AppColors.text),
                        const SizedBox(width: 6),
                        Text(
                          _visitor.visitorType.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                            letterSpacing: 0.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _StatusChip(
                    status: _visitor.status,
                    color: _statusColor(_visitor.status),
                    icon: _statusIcon(_visitor.status), // ✅ added icon
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.reject, color: AppColors.error.withOpacity(0.9)), // ✅
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _error = null),
            icon: const Icon(AppIcons.more), // ✅ (or AppIcons.back if you prefer)
            color: AppColors.error.withOpacity(0.9),
            tooltip: "Dismiss",
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayFlat = _visitor.flatNo.isNotEmpty ? _visitor.flatNo : _visitor.flatId;
    final statusColor = _statusColor(_visitor.status);

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: AppColors.bg,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          "Visitor Details",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background subtle gradient (premium)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primarySoft.withOpacity(0.65),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),

          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            children: [
              if (_error != null) ...[
                _errorBanner(),
                const SizedBox(height: 12),
              ],

              _photoHeader(),
              const SizedBox(height: 14),

              _premiumCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayFlat,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(AppIcons.phone, size: 16, color: AppColors.text2), // ✅
                        const SizedBox(width: 6),
                        Text(
                          _visitor.visitorPhone.isEmpty ? "No phone" : _visitor.visitorPhone,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text2,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: statusColor.withOpacity(0.30)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_statusIcon(_visitor.status), size: 14, color: statusColor), // ✅
                              const SizedBox(width: 6),
                              Text(
                                _visitor.status,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_visitor.residentPhone != null && _visitor.residentPhone!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final phone = _visitor.residentPhone!;
                          final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
                          if (cleaned.isEmpty) return;
                          final uri = Uri.parse('tel:$cleaned');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Icon(AppIcons.phone, size: 16, color: AppColors.success),
                            const SizedBox(width: 6),
                            Text(
                              "Resident (flat owner): ${_visitor.residentPhone}",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.call_rounded, size: 16, color: AppColors.success),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    const Text(
                      "Note (optional)",
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _noteController,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                        decoration: InputDecoration(
                          hintText: "Add a note for the resident (optional)…",
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          prefixIcon: Icon(AppIcons.note, color: AppColors.text2), // ✅
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Only show actions if visitor is still PENDING and viewer is allowed (e.g. resident); guards must not see Approve/Reject/Leave
              if (widget.showStatusActions && _isPending(_visitor.status)) ...[
                const SizedBox(height: 14),
                // Actions
                _premiumCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Actions",
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _loading ? null : () => _setStatus("APPROVED"),
                                icon: const Icon(AppIcons.approve, size: 18),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  disabledBackgroundColor: AppColors.success.withOpacity(0.5),
                                ),
                                label: const Text(
                                  "Approve",
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: _loading ? null : () => _setStatus("REJECTED"),
                                icon: const Icon(AppIcons.reject, size: 18),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: BorderSide(color: AppColors.error.withOpacity(0.28)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  backgroundColor: AppColors.surface,
                                  disabledForegroundColor: AppColors.error.withOpacity(0.5),
                                ),
                                label: const Text(
                                  "Reject",
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _setStatus("LEAVE_AT_GATE"),
                          icon: const Icon(AppIcons.leave, size: 18),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warning,
                            side: BorderSide(color: AppColors.warning.withOpacity(0.28)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: AppColors.surface,
                            disabledForegroundColor: AppColors.warning.withOpacity(0.5),
                          ),
                          label: const Text(
                            "Leave at Gate",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Show status info card for completed visitors
                const SizedBox(height: 14),
                _premiumCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _statusIcon(_visitor.status),
                            color: statusColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Status: ${_visitor.status}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_visitor.approvedAt != null) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 16, color: AppColors.text2),
                            const SizedBox(width: 8),
                            Text(
                              "Processed: ${_formatDateTime(_visitor.approvedAt!)}",
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.text2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),

          // Confetti when approval succeeds
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 25,
              maxBlastForce: 18,
              minBlastForce: 5,
              gravity: 0.25,
              colors: const [
                AppColors.success,
                AppColors.primary,
                Colors.orangeAccent,
                Colors.blueAccent,
              ],
            ),
          ),

          // Full screen glass loader
          AppLoader.overlay(
            show: _loading,
            message: "Updating status…",
          ),
        ],
      ),
      ),
    );
  }
}

/* ----------------- Small UI Widgets ----------------- */

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;
  final IconData icon; // ✅ added

  const _StatusChip({
    required this.status,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withOpacity(0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color), // ✅
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    );
  }
}
