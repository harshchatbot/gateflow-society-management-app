import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/storage.dart';
import '../core/app_logger.dart';
import '../core/session_gate_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import 'admin_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'admin_onboarding_screen.dart';
import 'admin_pending_approval_screen.dart';
import 'platform_super_admin_console_screen.dart';

enum _OtpStep { phone, otp }

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKeyPhone = GlobalKey<FormState>();
  final _formKeyOtp = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();

  bool _isLoading = false;

  _OtpStep _step = _OtpStep.phone;

  String? _verificationId;
  int? _resendToken;

  int _resendSeconds = 0;
  Timer? _resendTimer;

  bool get _canResend => _resendSeconds <= 0 && !_isLoading;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _startResendTimer({int seconds = 30}) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  String _maskPhone(String phoneE164) {
    // +91xxxxxxxxxx -> +91******xxxx
    if (phoneE164.length <= 6) return phoneE164;
    final last4 = phoneE164.substring(phoneE164.length - 4);
    return '${phoneE164.substring(0, 3)}******$last4';
  }

  Future<void> _sendOtp({bool forceResend = false}) async {
    if (_isLoading) return;
    if (!_formKeyPhone.currentState!.validate()) return;

    final raw = _phoneController.text.trim();
    final normalized = FirebaseAuthService.normalizePhoneForIndia(raw);

    setState(() => _isLoading = true);

    try {
      AppLogger.i("Admin OTP: sending code", data: {
        "phone": "masked",
        "forceResend": forceResend,
      });

      final res = await _authService.verifyPhoneNumber(
        phoneNumber: normalized,
        resendToken: forceResend ? _resendToken : null,
      );

      if (!mounted) return;
      setState(() {
        _verificationId = res.verificationId;
        _resendToken = res.resendToken;
        _step = _OtpStep.otp;
      });

      _startResendTimer(seconds: 30);

      // Focus OTP field
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_otpFocus);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("OTP sent to ${_maskPhone(normalized)}"),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } on FirebaseAuthException catch (e, st) {
      AppLogger.e("Admin OTP send failed", error: e, stackTrace: st);

      String msg = "Failed to send OTP. Please try again.";
      final code = e.code.toLowerCase();
      if (code.contains('invalid-phone-number')) {
        msg = "Invalid phone number. Please check and try again.";
      } else if (code.contains('too-many-requests')) {
        msg = "Too many attempts. Please wait and try again.";
      } else if (code.contains('network-request-failed')) {
        msg = "Network error. Please check your connection.";
      }
      _showError(msg);
    } catch (e, st) {
      AppLogger.e("Admin OTP send unknown error", error: e, stackTrace: st);
      _showError("Failed to send OTP. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtpAndLogin() async {
    if (_isLoading) return;
    if (!_formKeyOtp.currentState!.validate()) return;

    final verificationId = _verificationId;
    if (verificationId == null || verificationId.isEmpty) {
      if (!mounted) return;
      _showError("Session expired. Please request OTP again.");
      setState(() => _step = _OtpStep.phone);
      return;
    }

    final smsCode = _otpController.text.trim();
    if (smsCode.isEmpty || smsCode.length < 4) {
      if (!mounted) return;
      _showError("Please enter the OTP.");
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      AppLogger.i("Admin OTP: verifying code");

      final cred = await _authService.signInWithPhoneCredential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final uid = cred.user?.uid;
      if (uid == null) throw Exception("Failed to authenticate");

      // IMPORTANT: _postLogin() does membership resolve + recovery + navigation
      await _postLogin(uid: uid);
    } on FirebaseAuthException catch (e, st) {
      AppLogger.e("Admin OTP verify failed", error: e, stackTrace: st);

      final code = e.code.toLowerCase();
      String msg = "Invalid OTP. Please try again.";

      if (code == 'invalid-verification-code' ||
          code.contains('invalid-verification-code')) {
        msg = "Invalid OTP. Please check and try again.";
      } else if (code == 'session-expired' ||
          code.contains('session-expired')) {
        msg = "OTP expired. Please request a new OTP.";
      } else if (code == 'network-request-failed' ||
          code.contains('network-request-failed')) {
        msg = "Network error. Please check your connection.";
      } else if (code.contains('too-many-requests')) {
        msg = "Too many attempts. Please wait and try again.";
      }

      if (!mounted) return;
      _showError(msg);

      // For expired sessions, move back to phone step
      if (code == 'session-expired' || code.contains('session-expired')) {
        setState(() {
          _step = _OtpStep.phone;
          _verificationId = null;
          _otpController.clear();
        });
      }
    } catch (e, st) {
      AppLogger.e("Admin OTP verify unknown error", error: e, stackTrace: st);
      if (!mounted) return;
      _showError("Login failed. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Keeps your existing behavior:
  /// membership -> pending approval -> gate -> save session -> shell
  Future<void> _postLogin({required String uid}) async {
    final membership = await _firestore.getCurrentUserMembership();

    if (!mounted) return;

    // 🚫 No membership → onboarding
    if (membership == null) {
      final pendingSocietyRequest =
          await _firestore.getPendingSocietyCreationRequestForUser(uid: uid);
      if (pendingSocietyRequest != null) {
        final requestedSocietyId =
            (pendingSocietyRequest['proposedSocietyId'] ?? '')
                .toString()
                .trim();
        final requestedSocietyName =
            (pendingSocietyRequest['proposedName'] ?? '').toString().trim();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminPendingApprovalScreen(
              adminId: uid,
              societyId: requestedSocietyId.isNotEmpty
                  ? requestedSocietyId
                  : 'pending_society',
              adminName: (pendingSocietyRequest['requesterName'] ?? 'Admin')
                  .toString(),
              email: (pendingSocietyRequest['requesterPhone'] ??
                      _phoneController.text)
                  .toString(),
              title: "Society Setup Pending",
              badgeText: "Waiting for Sentinel verification",
              message: requestedSocietyName.isNotEmpty
                  ? "Your request for $requestedSocietyName is under review by Sentinel team."
                  : "Your request is under review by Sentinel team.",
            ),
          ),
        );
        return;
      }

      final platformAdmin = await _firestore.getPlatformAdminProfile(uid: uid);
      final platformRole =
          (platformAdmin?['role'] ?? platformAdmin?['systemRole'] ?? '')
              .toString()
              .toLowerCase();
      final platformActive = platformAdmin?['active'] == true;
      if (platformRole == 'super_admin' && platformActive) {
        if (!mounted) return;
        await Storage.saveFirebaseSession(
          uid: uid,
          societyId: 'platform',
          systemRole: 'super_admin',
          societyRole:
              (platformAdmin?['societyRole'] ?? 'SUPER_ADMIN').toString(),
          name: (platformAdmin?['name'] ?? 'Platform Admin').toString(),
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlatformSuperAdminConsoleScreen(
              adminName:
                  (platformAdmin?['name'] ?? 'Platform Admin').toString(),
            ),
          ),
        );
        return;
      }

      final pointer = await _firestore.getRootMemberPointer(uid: uid);
      final pointerRole =
          (pointer?['systemRole'] ?? '').toString().toLowerCase();
      final pointerActive = pointer?['active'] == true;
      final pointerSocietyId = (pointer?['societyId'] ?? '').toString().trim();

      if (pointerRole == 'admin' &&
          !pointerActive &&
          pointerSocietyId.isNotEmpty) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminPendingApprovalScreen(
              adminId: uid,
              societyId: pointerSocietyId,
              adminName: (pointer?['name'] ?? 'Admin').toString(),
              email: (pointer?['phone'] ?? '').toString(),
            ),
          ),
        );
        return;
      }

      if (pointerRole == 'super_admin') {
        AppLogger.w('Platform super admin profile missing', data: {'uid': uid});
        await FirebaseAuth.instance.signOut();
        await Storage.clearFirebaseSession();
        await Storage.clearAllSessions();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Super admin profile is not provisioned. Contact backend team.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminOnboardingScreen()),
      );
      return;
    }

    final String? societyId = membership['societyId'] as String?;
    final String systemRole =
        (membership['systemRole'] as String?)?.toLowerCase() ?? 'admin';
    final String? societyRole = membership['societyRole'] as String?;
    final String name = membership['name'] as String? ?? 'Admin';
    final bool isActive = membership['active'] == true;

    // 🚫 Not an admin at all
    if (systemRole != 'admin' && systemRole != 'super_admin') {
      _showError("You are not authorized as an admin.");
      return;
    }

    if (systemRole == 'super_admin') {
      await Storage.saveFirebaseSession(
        uid: uid,
        societyId:
            (societyId == null || societyId.isEmpty) ? 'platform' : societyId,
        systemRole: systemRole,
        societyRole: (societyRole ?? 'SUPER_ADMIN'),
        name: name,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PlatformSuperAdminConsoleScreen(
            adminName: name.isNotEmpty ? name : 'Platform Admin',
          ),
        ),
      );
      return;
    }

    // 🚫 Critical guard (society admin must have society)
    if (societyId == null || societyId.isEmpty) {
      _showError("Society not linked to this account.");
      return;
    }

    // ✅ ONLY admin needs approval
    if (systemRole == 'admin' && !isActive) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminPendingApprovalScreen(
            adminId: uid,
            societyId: societyId,
            adminName: name.isNotEmpty ? name : 'Admin',
          ),
        ),
      );
      return;
    }

    // 🔒 Gate inactive societies
    final gate = SessionGateService();
    final gateResult = await gate.validateSessionAfterLogin(uid);

    if (!gateResult.allowed) {
      await FirebaseAuth.instance.signOut();
      await Storage.clearFirebaseSession();
      await Storage.clearAllSessions();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );
      return;
    }

    // ✅ Save unified session
    await Storage.saveFirebaseSession(
      uid: uid,
      societyId: societyId,
      systemRole: systemRole,
      societyRole: societyRole,
      name: name,
    );

    if (!mounted) return;

    // ✅ Go to dashboard
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShellScreen(
          adminId: uid,
          adminName: name,
          societyId: societyId,
          role: (societyRole ?? 'ADMIN').toUpperCase(),
          systemRole: systemRole,
        ),
      ),
    );
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: cs.onSurface,
              size: 20,
            ),
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (_) => const OnboardingChooseRoleScreen()),
              );
            }
          },
        ),
      ),
      body: Stack(
        children: [
          // Calm background wash
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.12),
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  _buildHeader(context),
                  const SizedBox(height: 22),
                  _buildCard(context),
                  const SizedBox(height: 16),
                  _buildCreateSocietyCta(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          AppLoader.overlay(
              showAfter: const Duration(milliseconds: 300),
              show: _isLoading,
              message: "Verifying Admin…"),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: 190,
          height: 140,
          child: Image.asset(
            'assets/illustrations/illustration_login_admin.png',
            fit: BoxFit.contain,
            errorBuilder: (ctx, __, ___) => Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.admin_panel_settings_rounded,
                size: 64,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Admin Portal",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _step == _OtpStep.phone
              ? "Login using your phone number"
              : "Enter the OTP sent to your phone",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                "OTP secure login",
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(_step),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: _step == _OtpStep.phone
            ? Form(
                key: _formKeyPhone,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Phone number",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PremiumField(
                      controller: _phoneController,
                      focusNode: _phoneFocus,
                      label: "Enter mobile number",
                      hint: "e.g. 9876543210",
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _sendOtp(),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) {
                          return "Please enter your phone number";
                        }
                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                        if (digits.length < 10) {
                          return "Enter a valid phone number";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "SEND OTP",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "We’ll send a one-time password to verify your identity.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            : Form(
                key: _formKeyOtp,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "OTP",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PremiumField(
                      controller: _otpController,
                      focusNode: _otpFocus,
                      label: "Enter 6-digit OTP",
                      hint: "••••••",
                      icon: Icons.password_rounded,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verifyOtpAndLogin(),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return "Please enter OTP";
                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                        if (digits.length < 6) {
                          return "Enter a valid 6-digit OTP";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOtpAndLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "VERIFY & LOGIN",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _step = _OtpStep.phone;
                                    _otpController.clear();
                                    _verificationId = null;
                                  });
                                  FocusScope.of(context)
                                      .requestFocus(_phoneFocus);
                                },
                          icon: Icon(Icons.edit_rounded,
                              size: 16, color: cs.primary),
                          label: Text(
                            "Change phone",
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _canResend
                              ? () => _sendOtp(forceResend: true)
                              : null,
                          child: Text(
                            _canResend
                                ? "Resend OTP"
                                : "Resend in $_resendSeconds s",
                            style: TextStyle(
                              color: _canResend
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.45),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildCreateSocietyCta(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.add_business_rounded, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Create a new society",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Request Society Admin setup (email optional)",
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminOnboardingScreen()),
                    );
                  },
            child: Text(
              "START",
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.textInputAction,
    this.focusNode,
    this.keyboardType,
    this.onSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
      ),
    );
  }
}
