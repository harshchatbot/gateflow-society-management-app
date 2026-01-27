import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../services/resident_service.dart';
import '../core/app_logger.dart';
import '../widgets/status_chip.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Resident History Screen
/// 
/// Purpose: Read-only list of past visitor approvals/rejections
/// - Shows completed decisions (APPROVED/REJECTED)
/// - No actions - just viewing history
/// - Similar UI to approvals but read-only
/// 
/// Differences from Guard screens:
/// - No visitor creation or editing
/// - No guard-specific actions
/// - Focus on viewing past decisions only
class ResidentHistoryScreen extends StatefulWidget {
  final String residentId;
  final String societyId;
  final String flatNo;
  final VoidCallback? onBackPressed;

  const ResidentHistoryScreen({
    super.key,
    required this.residentId,
    required this.societyId,
    required this.flatNo,
    this.onBackPressed,
  });

  @override
  State<ResidentHistoryScreen> createState() => _ResidentHistoryScreenState();
}

class _ResidentHistoryScreenState extends State<ResidentHistoryScreen> {
  late final ResidentService _service = ResidentService(
    baseUrl: dotenv.env["API_BASE_URL"] ?? "http://192.168.29.195:8000",
  );

  List<dynamic> _history = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getHistory(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        limit: 50,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _history = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_history.length} history records");
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load history";
        });
        AppLogger.w("Failed to load history: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading history", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
            onPressed: () {
              // If we're in a tab navigation, switch to dashboard
              if (widget.onBackPressed != null) {
                widget.onBackPressed!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        title: const Text(
          "Approval History",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: _loadHistory,
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
                    onPressed: _loadHistory,
                    child: const Text("Retry"),
                  ),
                ],
              ),
            )
          else if (_history.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: AppColors.text2),
                  const SizedBox(height: 16),
                  const Text(
                    "No history yet",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your approval history will appear here",
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
              onRefresh: _loadHistory,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final record = _history[index];
                  return _buildHistoryCard(record);
                },
              ),
            ),
          GlassLoader(show: _isLoading, message: "Loading history…"),
        ],
      ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> record) {
    final visitorId = record['visitor_id']?.toString() ?? '';
    final visitorType = record['visitor_type']?.toString() ?? 'GUEST';
    final visitorPhone = record['visitor_phone']?.toString() ?? '';
    final status = record['status']?.toString() ?? 'UNKNOWN';
    final createdAt = record['created_at']?.toString() ?? '';
    final approvedAt = record['approved_at']?.toString() ?? '';

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
          if (approvedAt.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.check_circle_rounded,
              "Decided",
              _formatDateTime(approvedAt),
            ),
          ],
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
