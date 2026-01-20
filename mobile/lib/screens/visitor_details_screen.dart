import 'package:flutter/material.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';

// New UI system (no logic changes)
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';

class VisitorDetailsScreen extends StatefulWidget {
  final Visitor visitor;
  final String guardId;
  const VisitorDetailsScreen({
    super.key,
    required this.visitor,
    required this.guardId,
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

  @override
  void initState() {
    super.initState();
    _visitor = widget.visitor;
    _noteController.text = _visitor.note ?? "";
  }

  @override
  void dispose() {
    _noteController.dispose();
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
      } else {
        _error = res.error?.userMessage ?? "Failed to update status";
      }
    });
  }

  Color _statusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains("APPROV")) return AppColors.success;
    if (s.contains("REJECT")) return AppColors.error;
    if (s.contains("LEAVE")) return AppColors.warning;
    if (s.contains("PENDING")) return AppColors.text2;
    return AppColors.textMuted;
  }

  IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case "DELIVERY":
        return Icons.local_shipping_outlined;
      case "CAB":
        return Icons.local_taxi_outlined;
      case "GUEST":
        return Icons.person_outline_rounded;
      default:
        return Icons.badge_outlined;
    }
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
                      Icons.image_not_supported_outlined,
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
                  _StatusChip(status: _visitor.status, color: _statusColor(_visitor.status)),
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
          Icon(Icons.error_outline, color: AppColors.error.withOpacity(0.9)),
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
            icon: const Icon(Icons.close_rounded),
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

    // No functionality changed:
    // - Same _setStatus calls
    // - Same note usage
    // - Same data shown (with nicer layout)
    // - Loader replaced by GlassLoader

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: AppColors.bg,
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
                      "$displayFlat",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined, size: 16, color: AppColors.text2),
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
                          child: Text(
                            _visitor.status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                        decoration: const InputDecoration(
                          hintText: "Add a note for the resident (optional)…",
                          hintStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

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
                            child: ElevatedButton(
                              onPressed: () => _setStatus("APPROVED"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
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
                            child: OutlinedButton(
                              onPressed: () => _setStatus("REJECTED"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(color: AppColors.error.withOpacity(0.28)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: AppColors.surface,
                              ),
                              child: const Text(
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
                      child: OutlinedButton(
                        onPressed: () => _setStatus("LEAVE_AT_GATE"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.warning,
                          side: BorderSide(color: AppColors.warning.withOpacity(0.28)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: AppColors.surface,
                        ),
                        child: const Text(
                          "Leave at Gate",
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Full screen glass loader
          GlassLoader(
            show: _loading,
            message: "Updating status…",
          ),
        ],
      ),
    );
  }
}

/* ----------------- Small UI Widgets ----------------- */

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusChip({
    required this.status,
    required this.color,
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
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.25,
        ),
      ),
    );
  }
}
