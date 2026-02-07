import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/notice_service.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';

/// Admin Create Notice Screen
/// 
/// Allows admins to create new notices/announcements
/// Theme: Purple/Admin theme
class AdminCreateNoticeScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;

  const AdminCreateNoticeScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
  });

  @override
  State<AdminCreateNoticeScreen> createState() => _AdminCreateNoticeScreenState();
}

class _AdminCreateNoticeScreenState extends State<AdminCreateNoticeScreen> {
  late final NoticeService _service = NoticeService(
    baseUrl: Env.apiBaseUrl,
  );

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  
  String _selectedType = "GENERAL";
  String _selectedPriority = "NORMAL";
  bool _isLoading = false;

  // Notice types with user-friendly labels
  final Map<String, String> _noticeTypes = {
    "GENERAL": "Announcement",
    "SCHEDULE": "Event",
    "POLICY": "Policy",
    "EMERGENCY": "Alert",
    "MAINTENANCE": "Maintenance",
  };

  final List<String> _priorities = [
    "LOW",
    "NORMAL",
    "HIGH",
    "URGENT",
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _createNotice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _service.createNotice(
        societyId: widget.societyId,
        adminId: widget.adminId,
        adminName: widget.adminName,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        noticeType: _selectedType,
        priority: _selectedPriority,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.i("Notice created successfully");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Notice created successfully!",
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
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        _showError(result.error ?? "Failed to create notice");
      }
    } catch (e) {
      AppLogger.e("Error creating notice", error: e);
      _showError("Connection error. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.notices)) {
      return const ModuleDisabledPlaceholder();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text(
          "Create Notice",
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Notice Type Selection
                  const Text(
                    "Notice Type",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _noticeTypes.entries.map((entry) {
                      final type = entry.key; // Backend value (GENERAL, SCHEDULE, etc.)
                      final label = entry.value; // User-friendly label (Announcement, Event, etc.)
                      final isSelected = _selectedType == type;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedType = type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.admin.withOpacity(0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.admin : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            label, // Show user-friendly label
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? AppColors.admin : AppColors.text2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Priority Selection
                  const Text(
                    "Priority",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _priorities.map((priority) {
                      final isSelected = _selectedPriority == priority;
                      Color priorityColor = AppColors.admin;
                      if (priority == "URGENT") {
                        priorityColor = AppColors.error;
                      } else if (priority == "HIGH") priorityColor = AppColors.warning;
                      else if (priority == "LOW") priorityColor = AppColors.text2;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedPriority = priority),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? priorityColor.withOpacity(0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? priorityColor : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            priority,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? priorityColor : AppColors.text2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Title Field
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: "Title",
                      hintText: "Enter notice title",
                      prefixIcon: const Icon(Icons.title_rounded, color: AppColors.admin),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.admin, width: 2),
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Title is required";
                      }
                      if (value.trim().length < 5) {
                        return "Title must be at least 5 characters";
                      }
                      if (value.trim().length > 200) {
                        return "Title must be less than 200 characters";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Content Field
                  TextFormField(
                    controller: _contentController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: "Content",
                      hintText: "Enter notice content/details...",
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 120),
                        child: Icon(Icons.description_rounded, color: AppColors.admin),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.admin, width: 2),
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Content is required";
                      }
                      if (value.trim().length < 10) {
                        return "Content must be at least 10 characters";
                      }
                      if (value.trim().length > 5000) {
                        return "Content must be less than 5000 characters";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Create Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _createNotice,
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: const Text(
                        "Create Notice",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.admin,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          AppLoader.overlay(showAfter: const Duration(milliseconds: 300), show: _isLoading, message: "Creating notice…"),
        ],
      ),
    );
  }
}
