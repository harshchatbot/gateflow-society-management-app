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
import 'resident_notification_settings_screen.dart';
import 'resident_edit_phone_screen.dart';
import 'resident_edit_image_screen.dart';
import 'resident_edit_account_screen.dart';
import 'get_started_screen.dart';

/// Resident Profile Screen
/// 
/// Purpose: Display resident information and account settings
/// - Shows resident details (name, flat, society)
/// - Account information section
/// - Settings section with navigation
/// - Logout functionality
/// 
/// Theme: Green/Success theme (matching resident login and dashboard)
class ResidentProfileScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;
  final String? residentPhone;
  final VoidCallback? onBackPressed;
  final VoidCallback? onStartTourRequested;

  const ResidentProfileScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
    this.residentPhone,
    this.onBackPressed,
    this.onStartTourRequested,
  });

  @override
  State<ResidentProfileScreen> createState() => _ResidentProfileScreenState();
}

class _ResidentProfileScreenState extends State<ResidentProfileScreen> {
  bool _isLoggingOut = false;
  final FirestoreService _firestore = FirestoreService();
  String? _photoUrl;

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
      });
    } catch (e, st) {
      AppLogger.e("Error loading resident profile photo", error: e, stackTrace: st);
    }
  }

  Future<void> _handleDeactivate() async {
    // Show confirmation dialog with detailed explanation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.warning, size: 28),
            SizedBox(width: 12),
            Text(
              "Deactivate Account",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "This will deactivate your membership in this society.",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            Text("After deactivation:"),
            SizedBox(height: 8),
            Text("• You will be logged out"),
            Text("• You can join another society"),
            Text("• Only one active society at a time"),
            SizedBox(height: 12),
            Text(
              "Are you sure you want to continue?",
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error),
            ),
          ],
        ),
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
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              "Deactivate",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoggingOut = true);

    try {
      // Deactivate membership
      await _firestore.deactivateMember(
        societyId: widget.societyId,
        uid: widget.residentId,
      );

      // Sign out and clear session
      await FirebaseAuth.instance.signOut();
      await Storage.clearResidentSession();
      await Storage.clearFirebaseSession();
      SocietyModules.clear();

      AppLogger.i("Account deactivated successfully");

      if (!mounted) return;

      // Navigate to role select screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
        (route) => false,
      );
    } catch (e, st) {
      AppLogger.e("Error deactivating account", error: e, stackTrace: st);
      if (mounted) {
        setState(() => _isLoggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Error deactivating account. Please try again.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
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
      
      // 2. Clear resident session
      await Storage.clearResidentSession();
      
      // 3. Clear Firebase session storage
      await Storage.clearFirebaseSession();
      SocietyModules.clear();

      AppLogger.i("Resident session cleared - logout successful");

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
          ),
        );
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
        body: CustomScrollView(
          slivers: [
            // Green Gradient Profile Header
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: AppColors.success,
              automaticallyImplyLeading: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () {
                  // If we're in a tab navigation, switch to dashboard
                  if (widget.onBackPressed != null) {
                    widget.onBackPressed!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success,
                      AppColors.success.withOpacity(0.7),
                    ],
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
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white24,
                        backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                            ? CachedNetworkImageProvider(_photoUrl!)
                            : null,
                        child: (_photoUrl == null || _photoUrl!.isEmpty)
                            ? const Icon(
                                Icons.person_rounded,
                                size: 50,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.residentName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Flat ${widget.flatNo}",
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
                  // Account Information Section
                  _buildAccountInfoSection(),
                  const SizedBox(height: 20),

                  // Settings Section
                  _buildSettingsSection(),
                  const SizedBox(height: 30),

                  // Deactivate Account Button
                  _buildDeactivateButton(),
                  const SizedBox(height: 16),

                  // Logout Button
                  _buildLogoutButton(),
                  const SizedBox(height: 120), // Bottom nav spacer
                ],
              ),
            ),
          ),
        ], // closes slivers
        ), // closes CustomScrollView
      ), // closes Scaffold
    ); // closes PopScope
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
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
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
            value: widget.residentName,
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.home_rounded,
            label: "Flat Number",
            value: widget.flatNo,
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.apartment_rounded,
            label: "Society ID",
            value: widget.societyId,
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: "Resident ID",
            value: widget.residentId,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.success),
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

  Widget _buildSettingsSection() {
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
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingItem(
            icon: Icons.lightbulb_outline_rounded,
            title: "Get Started",
            subtitle: "Quick start guide & interactive tour",
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GetStartedScreen(
                    role: 'resident',
                    onStartTour: widget.onStartTourRequested,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 24),
          _buildSettingItem(
            icon: Icons.notifications_rounded,
            title: "Notifications",
            subtitle: "Manage notification preferences",
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ResidentNotificationSettingsScreen(
                    residentId: widget.residentId,
                    societyId: widget.societyId,
                    flatNo: widget.flatNo,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 24),
          _buildSettingItem(
            icon: Icons.phone_rounded,
            title: "Phone Number",
            subtitle: "Update your phone number",
            onTap: () async {
              final updatedPhone = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (context) => ResidentEditPhoneScreen(
                    residentId: widget.residentId,
                    currentPhone: widget.residentPhone ?? "",
                    societyId: widget.societyId,
                    flatNo: widget.flatNo,
                  ),
                ),
              );
              if (updatedPhone != null && mounted) {
                setState(() {});
              }
            },
          ),
          const Divider(height: 24),
          _buildSettingItem(
            icon: Icons.person_rounded,
            title: "Account Information",
            subtitle: "Edit your name and details",
            onTap: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => ResidentEditAccountScreen(
                    residentId: widget.residentId,
                    residentName: widget.residentName,
                    societyId: widget.societyId,
                    flatNo: widget.flatNo,
                  ),
                ),
              );
              if (updated == true && mounted) {
                setState(() {});
              }
            },
          ),
          const Divider(height: 24),
          _buildSettingItem(
            icon: Icons.image_rounded,
            title: "Profile Picture",
            subtitle: "Upload or change your photo",
            onTap: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => ResidentEditImageScreen(
                    residentId: widget.residentId,
                    societyId: widget.societyId,
                    flatNo: widget.flatNo,
                  ),
                ),
              );
              if (updated == true && mounted) {
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.success, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.text2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeactivateButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: _isLoggingOut ? null : _handleDeactivate,
        icon: const Icon(Icons.person_off_rounded, color: AppColors.warning),
        label: const Text(
          "DEACTIVATE ACCOUNT",
          style: TextStyle(
            color: AppColors.warning,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.warning, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
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
