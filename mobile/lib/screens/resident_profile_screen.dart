import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import 'onboarding_choose_role_screen.dart';
import 'resident_notification_settings_screen.dart';
import 'resident_edit_phone_screen.dart';
import 'profile_link_phone_screen.dart';
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
/// Theme: Unified primary (blue/indigo); no role-specific colors.
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
  String? _phone;
  String? _email;

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
        _phone = membership['phone'] as String?;
        _email = membership['email'] as String?;
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This will deactivate your membership in this society.",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text("After deactivation:"),
            const SizedBox(height: 8),
            const Text("• You will be logged out"),
            const Text("• You can join another society"),
            const Text("• Only one active society at a time"),
            const SizedBox(height: 12),
            Text(
              "Are you sure you want to continue?",
              style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).dividerColor),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
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
            backgroundColor: Theme.of(context).colorScheme.error,
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
              side: BorderSide(color: Theme.of(context).dividerColor),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
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
              backgroundColor: Theme.of(context).colorScheme.error,
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
            backgroundColor: Theme.of(context).colorScheme.error,
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: CustomScrollView(
          slivers: [
            // Profile header – unified primary theme
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: Theme.of(context).colorScheme.primary,
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
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.85),
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
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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

                  // Login options: Add phone / Add email (optional)
                  _buildLoginOptionsSection(),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
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
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.info_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Account Information",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
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

  Widget _buildLoginOptionsSection() {
    final hasPhone = (_phone ?? '').trim().isNotEmpty;
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    final hasRealEmail = userEmail != null &&
        userEmail.isNotEmpty &&
        !userEmail.contains('gateflow.local');
    if (hasPhone && hasRealEmail) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Login options", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 12),
          if (!hasPhone)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.phone_android_rounded, color: theme.colorScheme.primary),
              title: const Text("Add phone number", style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text("Recommended for easier login"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final added = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ProfileLinkPhoneScreen(societyId: widget.societyId, uid: widget.residentId),
                  ),
                );
                if (added == true) _loadProfilePhoto();
              },
            ),
          if (!hasPhone && !hasRealEmail) const Divider(height: 16),
          if (!hasRealEmail)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email_outlined, color: theme.colorScheme.primary),
              title: const Text("Add email (optional)", style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text("For recovery and optional login"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _showAddEmailDialog,
            ),
        ],
      ),
    );
  }

  Future<void> _showAddEmailDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final authService = FirebaseAuthService();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add email (optional)", style: TextStyle(fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email", hintText: "you@example.com"),
              ),
              const SizedBox(height: 12),
              TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
              const SizedBox(height: 12),
              TextField(controller: confirmController, obscureText: true, decoration: const InputDecoration(labelText: "Confirm password")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final pass = passwordController.text;
              final confirm = confirmController.text;
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid email")));
                return;
              }
              if (pass.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 6 characters")));
                return;
              }
              if (pass != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
                return;
              }
              try {
                await authService.linkWithEmailCredential(email: email, password: pass);
                if (!context.mounted) return;
                Navigator.of(context).pop(true);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e is FirebaseAuthException
                        ? (e.code == 'email-already-in-use' ? "This email is already in use." : "Could not add email.")
                        : "Something went wrong."),
                  ),
                );
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email added. You can now login with email too."), backgroundColor: AppColors.success),
      );
      _loadProfilePhoto();
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
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
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
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
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.settings_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
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
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
            : Icon(Icons.logout_rounded, color: Theme.of(context).colorScheme.error),
        label: Text(
          _isLoggingOut ? "Logging out..." : "LOGOUT",
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Theme.of(context).colorScheme.error, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
