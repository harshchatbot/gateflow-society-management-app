import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/app_colors.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import '../core/society_modules.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import 'onboarding_choose_role_screen.dart';
import 'get_started_screen.dart';
import 'profile_link_phone_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String guardId;
  final String guardName;
  final String societyId;
  final VoidCallback? onBackPressed;
  final VoidCallback? onStartTourRequested;

  const ProfileScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.societyId,
    this.onBackPressed,
    this.onStartTourRequested,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isOnDuty = true; // Duty Status Toggle
  bool _isLoadingProfile = true;
  String? _photoUrl;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _shiftController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  XFile? _localSelfie;
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _shiftController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final membership = await _firestore.getCurrentUserMembership();
      if (membership != null && membership['uid'] == widget.guardId) {
        setState(() {
          _photoUrl = membership['photoUrl'] as String?;
          _emailController.text = (membership['email'] ?? '') as String;
          _phoneController.text = (membership['phone'] ?? '') as String;
          _shiftController.text = (membership['shiftTimings'] ?? '') as String;
        });
      }
    } catch (e, st) {
      AppLogger.e("Load guard profile failed", error: e, stackTrace: st);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
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
          // If we're in a tab navigation (IndexedStack), switch to dashboard
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
          // Premium Profile Header
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.primary,
            automaticallyImplyLeading: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                // If we're in a tab navigation (IndexedStack), switch to dashboard
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
                    colors: [AppColors.primary, Color(0xFF1E40AF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: _pickAndUploadSelfie,
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white24,
                        backgroundImage: _localSelfie != null
                            ? FileImage(File(_localSelfie!.path))
                            : (_photoUrl != null && _photoUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(_photoUrl!)
                                : null) as ImageProvider<Object>?,
                        child: _localSelfie == null && (_photoUrl == null || _photoUrl!.isEmpty)
                            ? const Icon(Icons.person, size: 50, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.guardName,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      "Guard ID: ${widget.guardId}",
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
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
                  // 0. Account summary
                  _buildAccountInfoSection(),
                  const SizedBox(height: 20),

                  // Login options: Add phone (recommended), Add email (optional)
                  _buildLoginOptionsSection(),
                  const SizedBox(height: 20),

                  // 1. Duty Status & Shift Card
                  _buildDutyCard(),
                  const SizedBox(height: 20),

                  // Profile & Contact
                  _buildProfileForm(),
                  const SizedBox(height: 25),

                  // Password
                  _buildPasswordCard(),
                  const SizedBox(height: 25),

                  // Get Started (Quick Start + Interactive Tour)
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GetStartedScreen(
                            role: 'guard',
                            onStartTour: widget.onStartTourRequested,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.primary, size: 22),
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
                          Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Operational Tasks Grid
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("My Operations", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  _buildTaskGrid(),

                  const SizedBox(height: 30),

                  // 4. Logout Button
                  _buildLogoutButton(context),

                  const SizedBox(height: 120), // Nav Bar Spacer
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildDutyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Duty Status", style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(_isOnDuty ? "Currently ON-DUTY" : "OFF-DUTY", 
                style: TextStyle(color: _isOnDuty ? AppColors.success : AppColors.error, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          Switch.adaptive(
            value: _isOnDuty,
            activeColor: AppColors.success,
            onChanged: (v) => setState(() => _isOnDuty = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_rounded,
                  color: AppColors.primary,
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
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.person_rounded,
            label: "Name",
            value: widget.guardName,
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: "Guard ID",
            value: widget.guardId,
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.apartment_rounded,
            label: "Society ID",
            value: widget.societyId,
          ),
        ],
      ),
    );
  }

  /// Add phone (recommended) / Add email (optional) — mobile-first auth.
  Widget _buildLoginOptionsSection() {
    final hasPhone = _phoneController.text.trim().isNotEmpty;
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    final hasRealEmail = userEmail != null &&
        userEmail.isNotEmpty &&
        !userEmail.contains('gateflow.local');
    if (hasPhone && hasRealEmail) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Login options",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          if (!hasPhone)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.phone_android_rounded, color: AppColors.primary),
              title: const Text("Add phone number", style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text("Recommended for easier login"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final added = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ProfileLinkPhoneScreen(
                      societyId: widget.societyId,
                      uid: widget.guardId,
                    ),
                  ),
                );
                if (added == true) _loadProfile();
              },
            ),
          if (!hasPhone && !hasRealEmail) const Divider(height: 16),
          if (!hasRealEmail)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email_outlined, color: AppColors.primary),
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
                decoration: const InputDecoration(
                  labelText: "Email",
                  hintText: "you@example.com",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Confirm password"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final pass = passwordController.text;
              final confirm = confirmController.text;
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Enter a valid email")),
                );
                return;
              }
              if (pass.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Password must be at least 6 characters")),
                );
                return;
              }
              if (pass != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Passwords do not match")),
                );
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
                        ? (e.code == 'email-already-in-use'
                            ? "This email is already in use."
                            : "Could not add email. Try again.")
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
        const SnackBar(
          content: Text("Email added. You can now login with email too."),
          backgroundColor: AppColors.success,
        ),
      );
      _loadProfile();
    }
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
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
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

  Widget _buildProfileForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Contact & Shift",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: "Email",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: "Phone",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _shiftController,
            decoration: const InputDecoration(
              labelText: "Shift timings (e.g. 8am–4pm)",
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Save Profile",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Change Password",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: "New 4–6 digit password",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: "Confirm password",
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: _changePassword,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Update Password",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    try {
      await _firestore.updateGuardProfile(
        societyId: widget.societyId,
        uid: widget.guardId,
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        shiftTimings: _shiftController.text.trim().isEmpty ? null : _shiftController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Profile updated",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.e("Save guard profile failed", error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Failed to update profile",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadSelfie() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (picked == null) return;

      setState(() {
        _localSelfie = picked;
      });

      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child('societies/${widget.societyId}/guards/${widget.guardId}.jpg');
      final file = File(picked.path);
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();

      await _firestore.updateGuardProfile(
        societyId: widget.societyId,
        uid: widget.guardId,
        photoUrl: url,
      );

      setState(() {
        _photoUrl = url;
      });
    } catch (e, st) {
      AppLogger.e("Upload guard selfie failed", error: e, stackTrace: st);
    }
  }

  Future<void> _changePassword() async {
    final newPin = _newPinController.text.trim();
    final confirm = _confirmPinController.text.trim();

    if (newPin.length < 4 || newPin.length > 6 || int.tryParse(newPin) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must be 4–6 digits",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (newPin != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Passwords do not match",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("Not signed in");
      }
      await user.updatePassword(newPin);
      _newPinController.clear();
      _confirmPinController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Password updated",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.e("Update guard password failed", error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Failed to update password. Please login again and retry.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildTaskGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildTaskItem(Icons.qr_code_scanner_rounded, "Patrolling", "Next: 04:00 PM"),
        _buildTaskItem(Icons.language_rounded, "Language", "English"),
        _buildTaskItem(Icons.support_agent_rounded, "Helpdesk", "2 New Tasks"),
        _buildTaskItem(Icons.info_outline_rounded, "Society Info", widget.societyId),
      ],
    );
  }

  Widget _buildTaskItem(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            // 1. Sign out from Firebase Auth
            await FirebaseAuth.instance.signOut();
            
            // 2. Clear old session storage
            await Storage.clearGuardSession();
            
            // 3. Clear Firebase session storage
            await Storage.clearFirebaseSession();
            SocietyModules.clear();

            AppLogger.i("Guard session cleared - logout successful");
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
                (route) => false,
              );
            }
          } catch (e) {
            AppLogger.e("Error during guard logout", error: e);
            // Still navigate to role select even if logout fails
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
                (route) => false,
              );
            }
          }
        },
        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
        label: const Text("END SESSION", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w900)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}