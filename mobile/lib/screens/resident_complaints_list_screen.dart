import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/complaint_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/society_modules.dart';
import '../widgets/status_chip.dart';
import '../widgets/module_disabled_placeholder.dart';

/// Resident Complaints List Screen
/// 
/// Allows residents to view all their current and past complaints
/// Theme: Green/Resident theme
class ResidentComplaintsListScreen extends StatefulWidget {
  final String residentId;
  final String societyId;
  final String flatNo;
  final VoidCallback? onBackPressed;

  const ResidentComplaintsListScreen({
    super.key,
    required this.residentId,
    required this.societyId,
    required this.flatNo,
    this.onBackPressed,
  });

  @override
  State<ResidentComplaintsListScreen> createState() => _ResidentComplaintsListScreenState();
}

class _ResidentComplaintsListScreenState extends State<ResidentComplaintsListScreen> {
  late final ComplaintService _service = ComplaintService(
    baseUrl: Env.apiBaseUrl,
  );

  List<dynamic> _complaints = [];
  List<dynamic> _filteredComplaints = [];
  bool _isLoading = false;
  String? _error;
  String _selectedFilter = "ALL"; // ALL, PENDING, IN_PROGRESS, RESOLVED, REJECTED

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getResidentComplaints(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        residentId: widget.residentId,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _complaints = result.data!;
          _applyFilter();
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_complaints.length} complaints");
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load complaints";
        });
        AppLogger.w("Failed to load complaints: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading complaints", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  void _applyFilter() {
    if (_selectedFilter == "ALL") {
      setState(() {
        _filteredComplaints = _complaints;
      });
    } else {
      setState(() {
        _filteredComplaints = _complaints.where((complaint) {
          final status = (complaint['status'] ?? '').toString().toUpperCase();
          return status == _selectedFilter;
        }).toList();
      });
    }
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
    _applyFilter();
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
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
          "My Complaints",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded, color: AppColors.success, size: 20),
            ),
            onPressed: _isLoading ? null : _loadComplaints,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Filter Chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppColors.bg,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip("ALL", "All"),
                      const SizedBox(width: 8),
                      _buildFilterChip("PENDING", "Pending"),
                      const SizedBox(width: 8),
                      _buildFilterChip("IN_PROGRESS", "In Progress"),
                      const SizedBox(width: 8),
                      _buildFilterChip("RESOLVED", "Resolved"),
                      const SizedBox(width: 8),
                      _buildFilterChip("REJECTED", "Rejected"),
                    ],
                  ),
                ),
              ),

              // Results Count
              if (_filteredComplaints.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        "${_filteredComplaints.length} complaint${_filteredComplaints.length != 1 ? 's' : ''}",
                        style: TextStyle(
                          color: AppColors.text2,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // List
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
          AppLoader.overlay(show: _isLoading, message: "Loading complaints…"),
        ],
      ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => _onFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.success.withOpacity(0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.success : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.success : AppColors.text2,
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.text2,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadComplaints,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredComplaints.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 64,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == "ALL" ? "No complaints yet" : "No ${_selectedFilter.toLowerCase()} complaints",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFilter == "ALL"
                  ? "Raise a complaint from the dashboard to get started"
                  : "Try selecting a different filter",
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text2,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadComplaints,
      color: AppColors.success,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _filteredComplaints.length,
        itemBuilder: (context, index) {
          return _buildComplaintCard(_filteredComplaints[index]);
        },
      ),
    );
  }

  Widget _buildComplaintCard(Map<String, dynamic> complaint) {
    final title = (complaint['title'] ?? 'Untitled').toString();
    final description = (complaint['description'] ?? '').toString();
    final category = (complaint['category'] ?? 'GENERAL').toString();
    final status = (complaint['status'] ?? 'PENDING').toString();
    final visibility = (complaint['visibility'] ?? 'general').toString().toLowerCase();
    final isPersonal = visibility == 'personal';
    final photoUrl = (complaint['photoUrl'] ?? complaint['photo_url'] ?? '').toString().trim();
    final hasPhoto = photoUrl.isNotEmpty;
    final createdAt = complaint['created_at']?.toString() ?? '';
    final resolvedAt = complaint['resolved_at']?.toString();
    final adminResponse = complaint['admin_response']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showComplaintDetails(complaint);
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Category + Personal badge + Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                        if (isPersonal) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.textMuted.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_rounded, size: 12, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  "Personal",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    StatusChip(status: status, compact: true),
                  ],
                ),
                if (hasPhoto) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      photoUrl,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 140,
                        color: AppColors.bg,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 40),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Description Preview
                if (description.isNotEmpty)
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 12),

                // Footer: Date
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(createdAt),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComplaintDetails(Map<String, dynamic> complaint) {
    final title = (complaint['title'] ?? 'Untitled').toString();
    final description = (complaint['description'] ?? '').toString();
    final category = (complaint['category'] ?? 'GENERAL').toString();
    final status = (complaint['status'] ?? 'PENDING').toString();
    final photoUrl = (complaint['photoUrl'] ?? complaint['photo_url'] ?? '').toString().trim();
    final hasPhoto = photoUrl.isNotEmpty;
    final createdAt = complaint['created_at']?.toString() ?? '';
    final resolvedAt = complaint['resolved_at']?.toString();
    final adminResponse = complaint['admin_response']?.toString();
    final resolvedBy = complaint['resolved_by']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: AppColors.surface,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.report_problem_rounded, color: AppColors.success, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Complaint Details",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    photoUrl,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      color: AppColors.bg,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 48),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 24),
              _buildDetailSection("Title", title),
              _buildDetailSection("Category", category),
              _buildDetailSection("Status", status),
              _buildDetailSection("Description", description),
              _buildDetailSection("Created", _formatDateTime(createdAt)),
              if (resolvedAt != null && resolvedAt.isNotEmpty)
                _buildDetailSection("Resolved", _formatDateTime(resolvedAt)),
              if (resolvedBy != null && resolvedBy.isNotEmpty)
                _buildDetailSection("Resolved By", resolvedBy),
              if (adminResponse != null && adminResponse.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.admin_panel_settings_rounded, color: AppColors.success, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            "Admin Response",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        adminResponse,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return "Unknown";
    try {
      final dt = DateTime.parse(dateTimeStr.replaceAll("Z", "+00:00")).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final dateOnly = DateTime(dt.year, dt.month, dt.day);

      if (dateOnly == today) {
        return "Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      } else if (dateOnly == yesterday) {
        return "Yesterday ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      } else {
        return "${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      }
    } catch (e) {
      AppLogger.e("Error formatting date time", error: e, data: {"dateTimeStr": dateTimeStr});
      return dateTimeStr;
    }
  }
}
