import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../services/firestore_service.dart';
import 'onboarding_choose_role_screen.dart';
import 'admin_edit_image_screen.dart';
import 'super_admin_bulk_upload_screen.dart';
import 'get_started_screen.dart';

/// Admin Profile Screen
/// 
/// Displays admin information and account settings
/// Theme: Purple/Admin theme
class AdminProfileScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String societyId;
  final String role;
  final VoidCallback? onBackPressed;
  final VoidCallback? onStartTourRequested;

  const AdminProfileScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.societyId,
    required this.role,
    this.onBackPressed,
    this.onStartTourRequested,
  });

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _isLoggingOut = false;
  final FirestoreService _firestore = FirestoreService();
  String? _photoUrl;
  String? _email;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final membership = await _firestore.getCurrentUserMembership();
      if (!mounted || membership == null) return;

      setState(() {
        _photoUrl = membership['photoUrl'] as String?;
        _email = membership['email'] as String?;
        _phone = membership['phone'] as String?;
      });
    } catch (e, st) {
      AppLogger.e("Error loading admin profile photo", error: e, stackTrace: st);
    }
  }

  Future<void> _showUpdateEmailDialog() async {
    final controller = TextEditingController(text: _email ?? "");
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Update Email",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: "Email",
            hintText: "admin@example.com",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty || !value.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Please enter a valid email.",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _firestore.updateAdminProfile(
          societyId: widget.societyId,
          uid: widget.adminId,
          email: result,
        );
        await _loadProfilePhoto();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Email updated successfully",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e, st) {
        AppLogger.e("Error updating admin email", error: e, stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Failed to update email. Please try again.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showUpdatePhoneDialog() async {
    final controller = TextEditingController(text: _phone ?? "");
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Update Phone Number",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: "Phone Number",
            hintText: "+91 9876543210",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              final digits = value.replaceAll(RegExp(r'[^\d+]'), '');
              if (digits.length < 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Please enter a valid phone number.",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _firestore.updateAdminProfile(
          societyId: widget.societyId,
          uid: widget.adminId,
          phone: result,
        );
        await _loadProfilePhoto();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Phone number updated successfully",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e, st) {
        AppLogger.e("Error updating admin phone", error: e, stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Failed to update phone number. Please try again.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Logout",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.text,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              "Cancel",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              "Logout",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoggingOut = true);

    try {
      // 1. Sign out from Firebase Auth
      await FirebaseAuth.instance.signOut();
      
      // 2. Clear admin session
      await Storage.clearAdminSession();
      
      // 3. Clear Firebase session storage
      await Storage.clearFirebaseSession();
      SocietyModules.clear();

      AppLogger.i("Admin session cleared - logout successful");

      if (!mounted) return;

      // Navigate to role select screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
        (route) => false,
      );
    } catch (e) {
      AppLogger.e("Error during logout", error: e);
      if (mounted) {
        setState(() => _isLoggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Error during logout. Please try again.",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // Profile Header (purple theme)
          SliverAppBar(
            automaticallyImplyLeading: true,
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.admin, // Purple background
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                if (widget.onBackPressed != null) {
                  widget.onBackPressed!();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.admin, Color(0xFF7C3AED)], // Purple gradient
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white24,
                        backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                            ? CachedNetworkImageProvider(_photoUrl!)
                            : null,
                        child: (_photoUrl == null || _photoUrl!.isNotEmpty == false)
                            ? const Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 50,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.adminName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.role,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Profile Image Section
                  _buildProfileImageSection(),
                  const SizedBox(height: 20),
                  
                  // Account Information Section
                  _buildAccountInfoSection(),
                  const SizedBox(height: 20),

                  // Bulk Upload Section (Super Admin only)
                  if (widget.role.toUpperCase() == 'SUPER_ADMIN') ...[
                    _buildBulkUploadSection(),
                    const SizedBox(height: 20),
                  ],

                  // Get Started (Quick Start + Interactive Tour)
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GetStartedScreen(
                            role: widget.role,
                            onStartTour: widget.onStartTourRequested,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.admin.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.admin.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.admin.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.admin, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Get Started", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.text)),
                                SizedBox(height: 4),
                                Text("Quick start guide & interactive tour", style: TextStyle(fontSize: 13, color: AppColors.text2)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.admin),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Logout Button
                  _buildLogoutButton(),
                  const SizedBox(height: 120), // Bottom nav spacer
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileImageSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.image_rounded, size: 20, color: AppColors.admin),
              ),
              const SizedBox(width: 12),
              const Text(
                "Profile Picture",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminEditImageScreen(
                    adminId: widget.adminId,
                    societyId: widget.societyId,
                  ),
                ),
              );
              if (updated == true && mounted) {
                await _loadProfilePhoto();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.admin.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.admin.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.camera_alt_rounded, color: AppColors.admin, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Upload or change your photo",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.text2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.15), // Purple icon background
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline, size: 20, color: AppColors.admin), // Purple icon
              ),
              const SizedBox(width: 12),
              const Text(
                "Account Information",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            icon: Icons.person_rounded,
            label: "Name",
            value: widget.adminName,
            iconColor: AppColors.admin,
            iconBgColor: AppColors.admin.withOpacity(0.15),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: "Admin ID",
            value: widget.adminId,
            iconColor: AppColors.admin,
            iconBgColor: AppColors.admin.withOpacity(0.15),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.apartment_rounded,
            label: "Society ID",
            value: widget.societyId,
            iconColor: AppColors.admin,
            iconBgColor: AppColors.admin.withOpacity(0.15),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.admin_panel_settings_rounded,
            label: "Role",
            value: widget.role,
            iconColor: AppColors.admin,
            iconBgColor: AppColors.admin.withOpacity(0.15),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: "Email",
            value: _email?.isNotEmpty == true ? _email! : "Not set",
            iconColor: AppColors.admin,
            iconBgColor: AppColors.admin.withOpacity(0.15),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: "Phone",
            value: _phone?.isNotEmpty == true ? _phone! : "Not set",
            iconColor: AppColors.admin,
            iconBgColor: AppColors.admin.withOpacity(0.15),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showUpdateEmailDialog,
                  icon: const Icon(Icons.email_rounded, size: 18),
                  label: const Text(
                    "Update Email",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.admin.withOpacity(0.6)),
                    foregroundColor: AppColors.admin,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showUpdatePhoneDialog,
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: const Text(
                    "Update Phone",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.admin.withOpacity(0.6)),
                    foregroundColor: AppColors.admin,
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

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color iconColor = AppColors.primary,
    Color iconBgColor = AppColors.primarySoft,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
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
              const SizedBox(height: 2),
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
        ),
      ],
    );
  }

  Widget _buildBulkUploadSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.admin.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.upload_file_rounded, size: 20, color: AppColors.admin),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Bulk Upload Members",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "Upload guards and residents in bulk using CSV files. Download sample templates to get started.",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SuperAdminBulkUploadScreen(
                    societyId: widget.societyId,
                    adminId: widget.adminId,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.admin.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.admin.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.upload_file_rounded, color: AppColors.admin, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Open Bulk Upload",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.text2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: _isLoggingOut ? null : _handleLogout,
        icon: _isLoggingOut
            ? SizedBox(
                width: 20,
                height: 20,
                child: AppLoader.inline(size: 20),
              )
            : const Icon(Icons.logout_rounded, color: AppColors.error),
        label: Text(
          _isLoggingOut ? "Logging out..." : "LOGOUT",
          style: const TextStyle(
            color: AppColors.error,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
