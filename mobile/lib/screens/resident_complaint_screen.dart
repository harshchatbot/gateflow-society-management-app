import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../services/complaint_service.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../widgets/module_disabled_placeholder.dart';
import '../core/env.dart';

/// Resident Complaint Screen
/// 
/// Allows residents to raise complaints
/// Theme: Green/Resident theme
class ResidentComplaintScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;

  const ResidentComplaintScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentComplaintScreen> createState() => _ResidentComplaintScreenState();
}

class _ResidentComplaintScreenState extends State<ResidentComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final ComplaintService _service = ComplaintService(
    baseUrl: Env.apiBaseUrl,
  );

  String _selectedCategory = "GENERAL";
  /// 'general' = visible to everyone; 'personal' = visible to admins & guards only
  String _visibility = "general";
  bool _isLoading = false;
  bool _isSuccess = false;

  File? _complaintImage;
  final ImagePicker _picker = ImagePicker();
  final _uuid = const Uuid();

  final List<Map<String, String>> _categories = [
    {"value": "GENERAL", "label": "General"},
    {"value": "MAINTENANCE", "label": "Maintenance"},
    {"value": "SECURITY", "label": "Security"},
    {"value": "CLEANING", "label": "Cleaning"},
    {"value": "OTHER", "label": "Other"},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isSuccess = false;
    });

    try {
      String? photoUrl;
      if (_complaintImage != null) {
        photoUrl = await _uploadComplaintImage(_complaintImage!);
        if (!mounted) return;
      }

      final result = await _service.createComplaint(
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        residentId: widget.residentId,
        residentName: widget.residentName,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        visibility: _visibility,
        photoUrl: photoUrl,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });

        AppLogger.i("Complaint created successfully", data: result.data);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Complaint submitted successfully!",
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

        // Clear form after success
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _titleController.clear();
            _descriptionController.clear();
            setState(() {
              _isSuccess = false;
              _complaintImage = null;
            });
          }
        });
      } else {
        setState(() => _isLoading = false);
        _showError(result.error ?? "Failed to submit complaint");
        AppLogger.e("Failed to create complaint", error: result.error);
      }
    } catch (e) {
      AppLogger.e("Error creating complaint", error: e);
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
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<String?> _uploadComplaintImage(File file) async {
    try {
      final storage = FirebaseStorage.instance;
      final path = 'societies/${widget.societyId}/complaints/${_uuid.v4()}.jpg';
      final ref = storage.ref().child(path);
      await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await ref.getDownloadURL();
    } catch (e) {
      AppLogger.e('Complaint image upload failed', error: e);
      if (mounted) _showError('Image upload failed. Submitting without photo.');
      return null;
    }
  }

  Future<void> _pickComplaintImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked != null && mounted) {
        setState(() => _complaintImage = File(picked.path));
      }
    } catch (e) {
      if (mounted) _showError('Could not pick image.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SocietyModules.isEnabled(SocietyModuleIds.complaints)) {
      return const ModuleDisabledPlaceholder();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
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
          "Raise Complaint",
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
                  // Header Section
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.report_problem_rounded,
                          color: AppColors.success,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Submit a Complaint",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.text,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "We'll address your concern promptly",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.text2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Optional photo (optional)
                  const Text(
                    "Add photo (optional)",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text2,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _complaintImage == null ? _pickComplaintImage : null,
                    child: Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _complaintImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded, size: 40, color: AppColors.success.withOpacity(0.6)),
                                const SizedBox(height: 8),
                                const Text(
                                  "Tap to add a photo",
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                                ),
                              ],
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(_complaintImage!, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    onPressed: () => setState(() => _complaintImage = null),
                                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Category Selection
                  const Text(
                    "Category",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text2,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat["value"];
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCategory = cat["value"]!);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.success.withOpacity(0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.success
                                  : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            cat["label"]!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? AppColors.success
                                  : AppColors.text2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Title Field
                  const Text(
                    "Title",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text2,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _titleController,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: "Brief description of your complaint",
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.title_rounded, color: AppColors.success, size: 20),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Please enter a title";
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
                  ),
                  const SizedBox(height: 20),

                  // Description Field
                  const Text(
                    "Description",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text2,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _descriptionController,
                      maxLines: 6,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: "Provide detailed information about your complaint...",
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.description_rounded, color: AppColors.success, size: 20),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Please enter a description";
                        }
                        if (value.trim().length < 10) {
                          return "Description must be at least 10 characters";
                        }
                        if (value.trim().length > 2000) {
                          return "Description must be less than 2000 characters";
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Visibility: Personal (admins & guards only) vs General (visible to everyone)
                  const Text(
                    "Who can see this complaint?",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text2,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _visibility = "general"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: _visibility == "general"
                                  ? AppColors.success.withOpacity(0.15)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _visibility == "general"
                                    ? AppColors.success
                                    : AppColors.border,
                                width: _visibility == "general" ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.public_rounded,
                                      size: 18,
                                      color: _visibility == "general"
                                          ? AppColors.success
                                          : AppColors.text2,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "General",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: _visibility == "general"
                                            ? AppColors.success
                                            : AppColors.text2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Visible to everyone (society-level)",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _visibility = "personal"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: _visibility == "personal"
                                  ? AppColors.success.withOpacity(0.15)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _visibility == "personal"
                                    ? AppColors.success
                                    : AppColors.border,
                                width: _visibility == "personal" ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.lock_rounded,
                                      size: 18,
                                      color: _visibility == "personal"
                                          ? AppColors.success
                                          : AppColors.text2,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Personal",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: _visibility == "personal"
                                            ? AppColors.success
                                            : AppColors.text2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Admins & guards only (flat-specific)",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || _isSuccess ? null : _submitComplaint,
                      icon: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: AppLoader.inline(size: 20),
                            )
                          : const Icon(Icons.send_rounded, size: 22),
                      label: Text(
                        _isLoading
                            ? "Submitting..."
                            : _isSuccess
                                ? "Submitted!"
                                : "Submit Complaint",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppLoader.overlay(showAfter: const Duration(milliseconds: 300), show: _isLoading, message: "Submitting complaint…"),
        ],
      ),
    );
  }
}
