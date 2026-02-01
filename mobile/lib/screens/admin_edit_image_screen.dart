import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/firestore_service.dart';
import '../ui/app_loader.dart';

/// Edit Profile Image Screen for Admin
/// 
/// Allows admins to upload or change their profile image.
/// Theme: Purple/Admin theme
class AdminEditImageScreen extends StatefulWidget {
  final String adminId;
  final String societyId;
  final String? currentImagePath;

  const AdminEditImageScreen({
    super.key,
    required this.adminId,
    required this.societyId,
    this.currentImagePath,
  });

  @override
  State<AdminEditImageScreen> createState() => _AdminEditImageScreenState();
}

class _AdminEditImageScreenState extends State<AdminEditImageScreen> {
  final FirestoreService _firestore = FirestoreService();
  final _picker = ImagePicker();
  File? _selectedImage;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      AppLogger.e("Error picking image", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Failed to pick image. Please try again.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Please select an image first",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload to Firebase Storage (admins path)
      final storage = FirebaseStorage.instance;
      final ref = storage
          .ref()
          .child('societies/${widget.societyId}/admins/${widget.adminId}.jpg');
      final file = _selectedImage!;
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();

      // Update admin membership document with photoUrl
      await _firestore.updateAdminProfile(
        societyId: widget.societyId,
        uid: widget.adminId,
        photoUrl: url,
      );

      if (!mounted) return;

      AppLogger.i("Profile image uploaded successfully", data: {"photoUrl": url});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                "Profile image updated successfully",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppColors.admin,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e, st) {
      AppLogger.e("Error uploading image", error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Failed to upload image. Please try again.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          "Profile Image",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.border,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.admin.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.image_rounded,
                        color: AppColors.admin,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Profile Picture",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Upload or change your profile image",
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                
                // Image Preview
                GestureDetector(
                  onTap: () => _showImageSourceDialog(),
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.admin,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.admin.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _selectedImage != null
                          ? Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                            )
                          : widget.currentImagePath != null
                              ? CachedNetworkImage(
                                  imageUrl: widget.currentImagePath!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey.shade300,
                                    child: const Center(child: Icon(Icons.admin_panel_settings_rounded, size: 70, color: AppColors.text2)),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: AppColors.bg,
                                    child: const Icon(Icons.admin_panel_settings_rounded, size: 70, color: AppColors.text2),
                                  ),
                                )
                              : Container(
                                  color: AppColors.bg,
                                  child: const Icon(
                                    Icons.admin_panel_settings_rounded,
                                    size: 70,
                                    color: AppColors.text2,
                                  ),
                                ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Change Photo Button
                OutlinedButton.icon(
                  onPressed: () => _showImageSourceDialog(),
                  icon: const Icon(Icons.camera_alt_rounded, size: 20),
                  label: const Text(
                    "Change Photo",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    side: BorderSide(color: AppColors.admin, width: 1.5),
                    foregroundColor: AppColors.admin,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Upload Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _selectedImage == null
                        ? null
                        : _handleUpload,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: AppLoader.inline(size: 20),
                          )
                        : const Icon(Icons.cloud_upload_rounded, size: 22),
                    label: Text(
                      _isLoading ? "Uploading..." : "Upload Image",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.admin,
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
          if (_isLoading) AppLoader.overlay(show: true),
        ],
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.admin.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.image_rounded,
                      color: AppColors.admin,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Select Image Source",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: AppColors.admin, size: 22),
              ),
              title: const Text(
                "Take Photo",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              subtitle: Text(
                "Capture a new photo",
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library_rounded, color: AppColors.admin, size: 22),
              ),
              title: const Text(
                "Choose from Gallery",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              subtitle: Text(
                "Select from your photos",
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_selectedImage != null) ...[
              const Divider(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_rounded, color: AppColors.error, size: 22),
                ),
                title: const Text(
                  "Remove Photo",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.error,
                  ),
                ),
                subtitle: Text(
                  "Clear selected image",
                  style: TextStyle(fontSize: 13, color: AppColors.text2),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                  });
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
