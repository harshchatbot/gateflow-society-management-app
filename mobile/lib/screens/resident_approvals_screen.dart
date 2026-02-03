import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/resident_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/society_modules.dart';
import '../utils/error_messages.dart';
import '../widgets/status_chip.dart';
import '../widgets/module_disabled_placeholder.dart';
import '../widgets/error_retry_widget.dart';

/// Resident Approvals Screen
/// 
/// Purpose: List of pending visitor requests for resident's flat
/// - Shows pending visitors with details
/// - Approve/Reject buttons for each request
/// - Calls backend decision API on action
/// 
/// Theme: Green/Success theme (matching resident login)
class ResidentApprovalsScreen extends StatefulWidget {
  final String residentId;
  final String societyId;
  final String flatNo;
  final VoidCallback? onBackPressed;

  const ResidentApprovalsScreen({
    super.key,
    required this.residentId,
    required this.societyId,
    required this.flatNo,
    this.onBackPressed,
  });

  @override
  State<ResidentApprovalsScreen> createState() => _ResidentApprovalsScreenState();
}

class _ResidentApprovalsScreenState extends State<ResidentApprovalsScreen> {
  late final ResidentService _service = ResidentService(
    baseUrl: Env.apiBaseUrl,
  );

  List<dynamic> _pendingVisitors = [];
  bool _isLoading = false;
  String? _error;
  String? _processingVisitorId;

  @override
  void initState() {
    super.initState();
    _loadApprovals();
  }

  Future<void> _loadApprovals() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getApprovals(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _pendingVisitors = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_pendingVisitors.length} pending approvals");
      } else {
        setState(() {
          _isLoading = false;
          _error = userFriendlyMessageFromError(result.error ?? "Failed to load approvals");
        });
        AppLogger.w("Failed to load approvals: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading approvals", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = userFriendlyMessageFromError(e);
        });
      }
    }
  }

  Future<void> _handleDecision(String visitorId, String decision) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _processingVisitorId = visitorId;
    });

    try {
      final result = await _service.decide(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        residentId: widget.residentId,
        visitorId: visitorId,
        decision: decision,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.i("Decision successful: $decision for visitor $visitorId");
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  decision == "APPROVED" ? Icons.check_circle : Icons.cancel,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  decision == "APPROVED" ? "Visitor approved successfully" : "Visitor rejected",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: decision == "APPROVED" ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );

        // Reload approvals list
        _loadApprovals();
      } else {
        setState(() {
          _isLoading = false;
          _processingVisitorId = null;
        });
        _showError(userFriendlyMessageFromError(result.error ?? "Failed to process decision"));
        AppLogger.e("Decision failed: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error processing decision", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _processingVisitorId = null;
        });
        _showError(userFriendlyMessageFromError(e));
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.visitorManagement)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          // If we're in a tab navigation, switch to dashboard
          if (widget.onBackPressed != null) {
            widget.onBackPressed!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              // If we're in a tab navigation, switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        title: Text(
          "Pending Approvals",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Theme.of(context).dividerColor,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh_rounded, color: AppColors.success, size: 20),
            ),
            onPressed: _loadApprovals,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: SingleChildScrollView(
                child: ErrorRetryWidget(
                  errorMessage: _error!,
                  onRetry: _loadApprovals,
                  retryLabel: 'Retry',
                ),
              ),
            )
          else if (_pendingVisitors.isEmpty && !_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "All caught up!",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "No pending approvals",
                        style: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "All visitor requests are processed",
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _loadApprovals,
              color: AppColors.success,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pendingVisitors.length,
                itemBuilder: (context, index) {
                  final visitor = _pendingVisitors[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildVisitorCard(visitor),
                  );
                },
              ),
            ),
          AppLoader.overlay(show: _isLoading, message: "Processing…"),
        ],
      ),
      ),
    );
  }

  Widget _buildVisitorCard(Map<String, dynamic> visitor) {
    final visitorId = visitor['visitor_id']?.toString() ?? '';
    final visitorType = visitor['visitor_type']?.toString() ?? 'GUEST';
    final visitorPhone = visitor['visitor_phone']?.toString() ?? '';
    final visitorName = visitor['visitor_name']?.toString().trim();
    final deliveryPartner = visitor['delivery_partner']?.toString().trim();
    final deliveryPartnerOther = visitor['delivery_partner_other']?.toString().trim();
    final status = visitor['status']?.toString() ?? 'PENDING';
    final createdAt = visitor['created_at']?.toString() ?? '';
    final photoUrl = visitor['photo_url']?.toString() ?? visitor['photoUrl']?.toString();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final isProcessing = _processingVisitorId == visitorId;
    final hasDeliveryPartner = visitorType == 'DELIVERY' &&
        ((deliveryPartner != null && deliveryPartner.isNotEmpty) ||
            (deliveryPartnerOther != null && deliveryPartnerOther.isNotEmpty));
    final deliveryDisplay = hasDeliveryPartner
        ? (deliveryPartner == 'Other' ? (deliveryPartnerOther?.isNotEmpty == true ? deliveryPartnerOther! : 'Other') : (deliveryPartner ?? ''))
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Type + Delivery Partner chip (if DELIVERY) + Status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      visitorType,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              if (deliveryDisplay != null && deliveryDisplay.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          deliveryDisplay,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              StatusChip(status: status, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          
          // Visitor Details (with optional photo)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPhoto) ...[
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade300,
                        child: const Center(child: Icon(Icons.person_rounded, color: AppColors.success, size: 24)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.success.withOpacity(0.1),
                        child: const Icon(Icons.person_rounded, color: AppColors.success, size: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (visitorName != null && visitorName.isNotEmpty)
                      _buildCompactDetailRow(Icons.person_outline_rounded, visitorName),
                    if (visitorName != null && visitorName.isNotEmpty) const SizedBox(height: 6),
                    if (deliveryDisplay != null && deliveryDisplay.isNotEmpty)
                      _buildCompactDetailRow(Icons.local_shipping_outlined, 'Delivery: $deliveryDisplay'),
                    if (deliveryDisplay != null && deliveryDisplay.isNotEmpty) const SizedBox(height: 6),
                    _buildCompactDetailRow(Icons.phone_rounded, visitorPhone),
                    const SizedBox(height: 6),
                    _buildCompactDetailRow(Icons.access_time_rounded, _formatDateTime(createdAt)),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 14),
          
          // Action Buttons (Compact)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isProcessing || _isLoading
                      ? null
                      : () => _handleDecision(visitorId, "REJECTED"),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text(
                    "Reject",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: isProcessing || _isLoading
                      ? null
                      : () => _handleDecision(visitorId, "APPROVED"),
                  icon: isProcessing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: AppLoader.inline(size: 16),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    isProcessing ? "Processing..." : "Approve",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDetailRow(IconData icon, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return "Unknown";
    try {
      final dt = DateTime.parse(dateTimeStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dateDay = DateTime(dt.year, dt.month, dt.day);
      
      String dateStr;
      if (dateDay == today) {
        dateStr = "Today";
      } else if (dateDay == today.subtract(const Duration(days: 1))) {
        dateStr = "Yesterday";
      } else {
        dateStr = "${dt.day}/${dt.month}/${dt.year}";
      }
      
      return "$dateStr • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateTimeStr;
    }
  }
}
