import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/resident_service.dart';
import '../core/app_logger.dart';
import '../widgets/status_chip.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Resident Approvals Screen
/// 
/// Purpose: List of pending visitor requests for resident's flat
/// - Shows pending visitors with details
/// - Approve/Reject buttons for each request
/// - Calls backend decision API on action
/// 
/// Differences from Guard screens:
/// - No visitor creation (guards only)
/// - Focus on decision-making (approve/reject)
/// - Simpler UI - just list + actions
class ResidentApprovalsScreen extends StatefulWidget {
  final String residentId;
  final String societyId;
  final String flatNo;

  const ResidentApprovalsScreen({
    super.key,
    required this.residentId,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentApprovalsScreen> createState() => _ResidentApprovalsScreenState();
}

class _ResidentApprovalsScreenState extends State<ResidentApprovalsScreen> {
  late final ResidentService _service = ResidentService(
    baseUrl: dotenv.env["API_BASE_URL"] ?? "http://192.168.29.195:8000",
  );

  List<dynamic> _pendingVisitors = [];
  bool _isLoading = false;
  String? _error;

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
          _error = result.error ?? "Failed to load approvals";
        });
        AppLogger.w("Failed to load approvals: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading approvals", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  Future<void> _handleDecision(String visitorId, String decision) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

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
            content: Text(
              decision == "APPROVED" ? "Visitor approved" : "Visitor rejected",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: decision == "APPROVED" ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        // Reload approvals list
        _loadApprovals();
      } else {
        setState(() => _isLoading = false);
        _showError(result.error ?? "Failed to process decision");
        AppLogger.e("Decision failed: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error processing decision", error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Connection error. Please try again.");
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text(
          "Pending Approvals",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: _loadApprovals,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.text2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loadApprovals,
                    child: const Text("Retry"),
                  ),
                ],
              ),
            )
          else if (_pendingVisitors.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: AppColors.text2),
                  const SizedBox(height: 16),
                  const Text(
                    "No pending approvals",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "All visitor requests are processed",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _loadApprovals,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pendingVisitors.length,
                itemBuilder: (context, index) {
                  final visitor = _pendingVisitors[index];
                  return _buildVisitorCard(visitor);
                },
              ),
            ),
          GlassLoader(show: _isLoading, message: "Loading approvals…"),
        ],
      ),
    );
  }

  Widget _buildVisitorCard(Map<String, dynamic> visitor) {
    final visitorId = visitor['visitor_id']?.toString() ?? '';
    final visitorType = visitor['visitor_type']?.toString() ?? 'GUEST';
    final visitorPhone = visitor['visitor_phone']?.toString() ?? '';
    final status = visitor['status']?.toString() ?? 'PENDING';
    final createdAt = visitor['created_at']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Type + Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                visitorType,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
              StatusChip(label: status),
            ],
          ),
          const SizedBox(height: 12),
          
          // Visitor Details
          _buildDetailRow(Icons.phone_rounded, "Phone", visitorPhone),
          const SizedBox(height: 8),
          _buildDetailRow(Icons.access_time_rounded, "Requested", _formatDateTime(createdAt)),
          
          const SizedBox(height: 16),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _handleDecision(visitorId, "REJECTED"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Reject",
                    style: TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _handleDecision(visitorId, "APPROVED"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Approve",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.text2),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 13,
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return "Unknown";
    try {
      final dt = DateTime.parse(dateTimeStr);
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateTimeStr;
    }
  }
}
