import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gateflow/models/visitor.dart';
import 'package:gateflow/services/visitor_service.dart';
import 'package:gateflow/services/offline_queue_service.dart';
import 'package:gateflow/services/favorite_visitors_service.dart';

// New UI system (no logic changes)
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../ui/sentinel_theme.dart';
import '../ui/visitor_chip_config.dart';

// ✅ Phosphor icon mapping (single source)
import '../ui/app_icons.dart';
import '../utils/error_messages.dart';
import '../widgets/sentinel_illustration.dart';
import '../widgets/error_retry_widget.dart';
import 'new_visitor_screen.dart';

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
  static const Color _favoriteGold = Color(0xFFC9A227);
  final _service = VisitorService();
  final FavoriteVisitorsService _favoritesService =
      FavoriteVisitorsService.instance;
  bool _loading = false;
  bool _favoriteLoading = false;
  bool _isFavoriteForUnit = false;
  String? _error;
  String? _lastAttemptedStatus;
  late Visitor _visitor;

  /// Last known status; used to detect transition to APPROVED (one-time confetti).
  String? _previousStatus;

  final _noteController = TextEditingController();
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _visitor = widget.visitor;
    _previousStatus = widget.visitor.status;
    _noteController.text = _visitor.note ?? "";
    _confettiController = ConfettiController(duration: const Duration(milliseconds: 600));
    _refreshFavoriteStatus();
  }

  @override
  void didUpdateWidget(covariant VisitorDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStatus = (oldWidget.visitor.status).toUpperCase();
    final newStatus = (widget.visitor.status).toUpperCase();
    if (oldStatus != 'APPROVED' && newStatus == 'APPROVED') {
      _visitor = widget.visitor;
      _previousStatus = widget.visitor.status;
      _confettiController.play();
    } else {
      _visitor = widget.visitor;
      _previousStatus = widget.visitor.status;
    }
    if (oldWidget.visitor.visitorId != widget.visitor.visitorId) {
      _refreshFavoriteStatus();
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(String status) async {
    final queue = OfflineQueueService.instance;
    await queue.ensureInit();
    if (!queue.isOnline) {
      await queue.enqueueUpdateStatus(
        visitorId: _visitor.visitorId,
        status: status,
        approvedBy: "GUARD:${widget.guardId}",
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Offline – changes will sync when online'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
      );
      return;
    }

    _lastAttemptedStatus = status;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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
          _lastAttemptedStatus = null;
          final newVisitor = res.data!;
          final prev = (_previousStatus ?? _visitor.status).toUpperCase();
          final now = newVisitor.status.toUpperCase();
          _visitor = newVisitor;
          _previousStatus = newVisitor.status;
          // One-time confetti only when status transitions to APPROVED
          if (prev != 'APPROVED' && now == 'APPROVED') {
            _confettiController.play();
          }
        } else {
          final friendly = userFriendlyMessageFromError(res.error ?? "Failed to update status");
          _error = friendly;
          _showStatusErrorDialog(friendly, status);
        }
      });
    } catch (err) {
      if (!mounted) return;
      final friendly = ErrorMessages.userFriendlyMessage(err);
      setState(() {
        _loading = false;
        _error = friendly;
      });
      _showStatusErrorDialog(friendly, status);
    }
  }

  Future<void> _showStatusErrorDialog(String message, String status) async {
    if (!mounted) return;
    final retryText = ErrorMessages.retryLabel(message);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Could not update status'),
          content: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            if (retryText.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _setStatus(status);
                },
                child: Text(retryText),
              ),
          ],
        );
      },
    );
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

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    if (diff.inDays == 1) return "Yesterday";
    if (diff.inDays < 7) return "${diff.inDays} days ago";
    return _formatDateTime(dateTime);
  }

  /// "Approved by Resident • 2 min ago" etc. Null when PENDING or no approvedAt.
  String? _lastActionLine() {
    if (_isPending(_visitor.status)) return null;
    final at = _visitor.approvedAt;
    if (at == null) return null;
    final s = _visitor.status.toUpperCase();
    final by = (_visitor.approvedBy ?? "").toUpperCase();
    final who = (by.contains("GUARD") ? "Guard" : "Resident");
    final String action;
    if (s.contains("APPROV")) {
      action = "Approved by $who";
    } else if (s.contains("REJECT")) {
      action = "Rejected by $who";
    } else if (s.contains("LEAVE")) {
      action = "Left at gate";
    } else {
      action = "Processed";
    }
    return "$action • ${_formatTimeAgo(at)}";
  }

  Future<void> _refreshFavoriteStatus() async {
    if (widget.showStatusActions) return;

    final unitIdRaw = _visitor.flatNo.trim().isNotEmpty
        ? _visitor.flatNo.trim()
        : _visitor.flatId.trim();
    final name = (_visitor.visitorName ?? '').trim();
    final phone = _visitor.visitorPhone.trim();

    if (unitIdRaw.isEmpty || (name.isEmpty && phone.isEmpty)) {
      if (!mounted) return;
      setState(() {
        _favoriteLoading = false;
        _isFavoriteForUnit = false;
      });
      return;
    }

    setState(() => _favoriteLoading = true);
    final key = FavoriteVisitorsService.buildVisitorKey(
      name: name.isEmpty ? phone : name,
      phone: phone,
      purpose: _visitor.visitorType,
    );
    final match = await _favoritesService.isFavoriteVisitor(
      societyId: _visitor.societyId,
      unitId: unitIdRaw,
      visitorKey: key,
    );
    if (!mounted) return;
    setState(() {
      _favoriteLoading = false;
      _isFavoriteForUnit = match;
    });
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
              CachedNetworkImage(
                imageUrl: _visitor.photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey.shade300,
                  child: Center(
                    child: Icon(AppIcons.more, color: AppColors.textMuted.withOpacity(0.8), size: 40),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.bg,
                  child: Center(
                    child: Icon(
                      AppIcons.more,
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

            // Status chip + type label overlay; when PENDING and guard, show one-tap Allow/Deny
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                                CurvedAnimation(parent: animation, curve: Curves.easeOut),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: _StatusChip(
                          key: ValueKey<String>(_visitor.status),
                          status: _visitor.status,
                          color: _statusColor(_visitor.status),
                          icon: _statusIcon(_visitor.status),
                        ),
                      ),
                    ],
                  ),
                  if (_isPending(_visitor.status) && !widget.showStatusActions) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _loading ? null : () => _setStatus("APPROVED"),
                            style: FilledButton.styleFrom(
                              backgroundColor: SentinelStatusPalette.success,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Allow Entry", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : () => _setStatus("REJECTED"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SentinelStatusPalette.error,
                              side: const BorderSide(color: SentinelStatusPalette.error),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Deny", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ],
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
    return ErrorRetryWidget(
      errorMessage: _error!,
      retryLabel: 'Retry',
      onRetry: () {
        setState(() => _error = null);
        if (_lastAttemptedStatus != null) _setStatus(_lastAttemptedStatus!);
      },
    );
  }

  String _illustrationKindForType(String visitorType) {
    switch (visitorType.toUpperCase()) {
      case 'CAB':
        return 'cab';
      case 'DELIVERY':
        return 'delivery';
      default:
        return 'visitor';
    }
  }

  Widget? _readOnlyProviderChip(BuildContext context) {
    final type = _visitor.visitorType.toUpperCase();
    if (type != 'CAB' && type != 'DELIVERY') return null;
    ChipGroupConfig? config;
    try {
      config = visitorChipGroups.firstWhere((g) => g.visitorType == type);
    } catch (_) {
      return null;
    }
    final provider = type == 'CAB'
        ? (_visitor.cab?['provider'] as String?)
        : (_visitor.delivery?['provider'] as String?);
    if (provider == null || provider.trim().isEmpty) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SentinelColors.accentSurface(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SentinelColors.accentBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 16, color: SentinelColors.accent),
          const SizedBox(width: 8),
          Text(
            provider.trim(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SentinelColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayFlat = _visitor.flatNo.isNotEmpty ? _visitor.flatNo : _visitor.flatId;
    final statusColor = _statusColor(_visitor.status);
    final readOnlyProviderChip = _readOnlyProviderChip(context);
    final lastActionLine = _lastActionLine();

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

              SentinelIllustration(
                kind: _illustrationKindForType(_visitor.visitorType),
                height: 110,
              ),
              const SizedBox(height: 14),
              if (readOnlyProviderChip != null) ...[
                readOnlyProviderChip,
                const SizedBox(height: 14),
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
                        const Icon(AppIcons.phone, size: 16, color: AppColors.text2), // ✅
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
                    if (!widget.showStatusActions && _isFavoriteForUnit) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.24),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 15,
                              color: _favoriteGold,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Favourite for this unit",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (!widget.showStatusActions && _favoriteLoading) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Checking favourites...",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (lastActionLine != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        lastActionLine,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (!_isPending(_visitor.status)) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => NewVisitorScreen(
                                guardId: widget.guardId,
                                guardName: '',
                                societyId: _visitor.societyId,
                                initialVisitor: _visitor,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Repeat visitor'),
                      ),
                    ],
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
                            const Icon(AppIcons.phone, size: 16, color: AppColors.success),
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
                    if (_visitor.visitorType.toUpperCase() == 'CAB' &&
                        _visitor.cab != null &&
                        _visitor.cab!['provider'] != null &&
                        (_visitor.cab!['provider'] as String).trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(AppIcons.cab, size: 16, color: AppColors.text2),
                          const SizedBox(width: 6),
                          Text(
                            "Cab Provider: ${_visitor.cab!['provider']}",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_visitor.visitorType.toUpperCase() == 'DELIVERY' &&
                        _visitor.delivery != null &&
                        _visitor.delivery!['provider'] != null &&
                        (_visitor.delivery!['provider'] as String).trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(AppIcons.delivery, size: 16, color: AppColors.text2),
                          const SizedBox(width: 6),
                          Text(
                            "Delivery Partner: ${_visitor.delivery!['provider']}",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text2,
                            ),
                          ),
                        ],
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
                        decoration: const InputDecoration(
                          hintText: "Add a note for the resident (optional)…",
                          hintStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                            const Icon(Icons.access_time_rounded, size: 16, color: AppColors.text2),
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

          // One-time confetti when status transitions to APPROVED (does not intercept gestures)
          IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.05,
                numberOfParticles: 22,
                maxBlastForce: 14,
                minBlastForce: 4,
                gravity: 0.4,
                colors: [
                  SentinelColors.accent,
                  SentinelStatusPalette.success.withOpacity(0.8),
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                ],
              ),
            ),
          ),

          // Full screen glass loader
          AppLoader.overlay(showAfter: const Duration(milliseconds: 300), 
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
    super.key,
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
