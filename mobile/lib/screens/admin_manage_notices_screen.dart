import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/notice_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';
import 'admin_create_notice_screen.dart';

/// Admin Manage Notices Screen
/// 
/// Allows admins to view and manage all notices
/// Theme: Purple/Admin theme
class AdminManageNoticesScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final VoidCallback? onBackPressed;

  const AdminManageNoticesScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    this.onBackPressed,
  });

  @override
  State<AdminManageNoticesScreen> createState() => _AdminManageNoticesScreenState();
}

class _AdminManageNoticesScreenState extends State<AdminManageNoticesScreen> {
  late final NoticeService _service = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );

  List<dynamic> _notices = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getNotices(
        societyId: widget.societyId,
        activeOnly: false, // Show all for admin
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _notices = result.data!;
          _isLoading = false;
        });
        AppLogger.i("Loaded ${_notices.length} notices");
      } else {
        setState(() {
          _isLoading = false;
          _error = result.error ?? "Failed to load notices";
        });
        AppLogger.w("Failed to load notices: ${result.error}");
      }
    } catch (e) {
      AppLogger.e("Error loading notices", error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Connection error. Please try again.";
        });
      }
    }
  }

  Future<void> _deleteNotice(String noticeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Delete Notice?",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text("This will permanently delete the notice from the system. This action cannot be undone."),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.text,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _service.deleteNotice(noticeId: noticeId);

      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.i("Notice deleted successfully");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Notice deleted successfully",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        _loadNotices();
      } else {
        _showError(result.error ?? "Failed to delete notice");
      }
    } catch (e) {
      AppLogger.e("Error deleting notice", error: e);
      _showError("Connection error. Please try again.");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      return ModuleDisabledPlaceholder(onBack: widget.onBackPressed);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () {
            if (widget.onBackPressed != null) {
              widget.onBackPressed!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          "Manage Notices",
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
                color: AppColors.admin.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.admin, size: 24),
            ),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminCreateNoticeScreen(
                    adminId: widget.adminId,
                    adminName: widget.adminName,
                    societyId: widget.societyId,
                  ),
                ),
              );
              if (result == true) {
                _loadNotices();
              }
            },
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.admin.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded, color: AppColors.admin, size: 20),
            ),
            onPressed: _isLoading ? null : _loadNotices,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          _buildContent(),
          AppLoader.overlay(show: _isLoading, message: "Loading notices…"),
        ],
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
              onPressed: _loadNotices,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.admin,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_notices.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.admin.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 64,
                color: AppColors.admin,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "No notices yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Create your first notice to get started",
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text2,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminCreateNoticeScreen(
                      adminId: widget.adminId,
                      adminName: widget.adminName,
                      societyId: widget.societyId,
                    ),
                  ),
                );
                if (result == true) {
                  _loadNotices();
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text("Create Notice"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.admin,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotices,
      color: AppColors.admin,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _notices.length,
        itemBuilder: (context, index) {
          return _buildNoticeCard(_notices[index]);
        },
      ),
    );
  }

  Widget _buildNoticeCard(Map<String, dynamic> notice) {
    final title = (notice['title'] ?? 'Untitled').toString();
    final content = (notice['content'] ?? '').toString();
    final noticeType = (notice['notice_type'] ?? 'GENERAL').toString();
    final priority = (notice['priority'] ?? 'NORMAL').toString();
    final isActive = (notice['is_active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE';
    final createdAt = notice['created_at']?.toString() ?? '';
    final noticeId = (notice['notice_id'] ?? '').toString();

    Color priorityColor = AppColors.admin;
    if (priority == "URGENT") priorityColor = AppColors.error;
    else if (priority == "HIGH") priorityColor = AppColors.warning;
    else if (priority == "LOW") priorityColor = AppColors.text2;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? priorityColor.withOpacity(0.3)
              : AppColors.border.withOpacity(0.5),
          width: isActive ? 1.5 : 1,
        ),
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
          onTap: () => _showNoticeDetails(notice),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Type + Priority + Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.admin.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            noticeType,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.admin,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: priorityColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            priority,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: priorityColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.success.withOpacity(0.15)
                            : AppColors.text2.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? "ACTIVE" : "INACTIVE",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isActive ? AppColors.success : AppColors.text2,
                        ),
                      ),
                    ),
                  ],
                ),
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

                // Content Preview
                if (content.isNotEmpty)
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 12),

                // Footer: Date + Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.admin.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: AppColors.admin,
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
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      color: AppColors.error,
                      onPressed: () => _deleteNotice(noticeId),
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

  void _showNoticeDetails(Map<String, dynamic> notice) {
    final title = (notice['title'] ?? 'Untitled').toString();
    final content = (notice['content'] ?? '').toString();
    final noticeType = (notice['notice_type'] ?? 'GENERAL').toString();
    final priority = (notice['priority'] ?? 'NORMAL').toString();
    final isActive = (notice['is_active'] ?? 'TRUE').toString().toUpperCase() == 'TRUE';
    final createdAt = notice['created_at']?.toString() ?? '';
    final adminName = (notice['admin_name'] ?? 'Unknown').toString();

    Color priorityColor = AppColors.admin;
    if (priority == "URGENT") priorityColor = AppColors.error;
    else if (priority == "HIGH") priorityColor = AppColors.warning;
    else if (priority == "LOW") priorityColor = AppColors.text2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: AppColors.surface,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
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
                      color: AppColors.admin.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_rounded, color: AppColors.admin, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Notice Details",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailSection("Title", title),
              _buildDetailSection("Type", noticeType),
              _buildDetailSection("Priority", priority),
              _buildDetailSection("Status", isActive ? "ACTIVE" : "INACTIVE"),
              _buildDetailSection("Created By", adminName),
              _buildDetailSection("Created", _formatDateTime(createdAt)),
              _buildDetailSection("Content", content),
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
