import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../core/session_gate_service.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import 'admin_shell_screen.dart';
import 'admin_signup_screen.dart';
import 'find_society_screen.dart';
import 'guard_join_screen.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'resident_shell_screen.dart';

/// Nice centered auth card
class _AuthCard extends StatelessWidget {
  final Widget child;
  const _AuthCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: child,
    );
  }
}

/// Phone OTP login (primary auth). Enter phone → OTP → verify → gate → route.
/// No OTPs stored; Firebase session persistence respected.
class PhoneOtpLoginScreen extends StatefulWidget {
  /// Optional: guard | resident | admin — for subtitle only; routing uses membership.
  final String? roleHint;

  const PhoneOtpLoginScreen({super.key, this.roleHint});

  @override
  State<PhoneOtpLoginScreen> createState() => _PhoneOtpLoginScreenState();
}

class _PhoneOtpLoginScreenState extends State<PhoneOtpLoginScreen> {
  final _authService = FirebaseAuthService();
  final _firestore = FirestoreService();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  String? _verificationId;
  int? _resendToken;
  bool _isLoading = false;
  String? _errorMessage;
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String get _normalizedPhone =>
      FirebaseAuthService.normalizePhoneForIndia(_phoneController.text.trim());

  Future<void> _sendOtp() async {
    final phone = _normalizedPhone;
    if (phone.length < 10) {
      setState(() {
        _errorMessage = 'Enter a valid 10-digit mobile number';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _authService.verifyPhoneNumber(
        phoneNumber: phone,
        resendToken: _resendToken,
      );
      if (!mounted) return;
      setState(() {
        _verificationId = result.verificationId;
        _resendToken = result.resendToken;
        _codeSent = true;
        _isLoading = false;
        _otpController.clear();
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyPhoneError(e.code);
      });
    } catch (e, st) {
      AppLogger.e('Phone OTP send failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not send OTP. Check number and try again.';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim().replaceAll(RegExp(r'[^\d]'), '');
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit OTP');
      return;
    }
    if (_verificationId == null) {
      setState(() => _errorMessage = 'Please request OTP again');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithPhoneCredential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Sign-in failed. Try again.';
        });
        return;
      }

      Map<String, dynamic>? membership =
          await _firestore.getCurrentUserMembership();
      final role = widget.roleHint?.toLowerCase();

      if (membership == null) {
        // No membership yet.
        if (!mounted) return;
        setState(() => _isLoading = false);

        Widget? target;
        if (role == 'guard') {
          target = const GuardJoinScreen();
        } else if (role == 'resident') {
          target = const FindSocietyScreen();
        } else if (role == 'admin') {
          target = const AdminSignupScreen();
        }

        if (target != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => target!),
          );
        } else {
          _showNoAccountDialog();
        }
        return;
      }

      // Ensure phone is saved on member (required for mobile-first profile).
      final phoneNumber = FirebaseAuth.instance.currentUser?.phoneNumber;
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        final societyIdForPhone = membership['societyId']?.toString() ?? '';
        if (societyIdForPhone.isNotEmpty) {
          try {
            await _firestore.setMemberPhone(
              societyId: societyIdForPhone,
              uid: uid,
              normalizedE164: phoneNumber,
            );
          } catch (_) {
            // Non-fatal: member may already have phone set or permission issue
          }
        }
      }

      final gate = SessionGateService();
      final gateResult = await gate.validateSessionAfterLogin(uid);
      if (!mounted) return;
      if (!gateResult.allowed) {
        await FirebaseAuth.instance.signOut();
        await Storage.clearAllSessions();
        await Storage.clearFirebaseSession();
        setState(() => _isLoading = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
        );
        if (gateResult.userMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(gateResult.userMessage!),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final societyId = membership['societyId']?.toString() ?? '';
      final systemRole = membership['systemRole']?.toString() ?? '';
      final name = membership['name']?.toString() ?? '';
      final flatNo = membership['flatNo']?.toString();
      final societyRole = membership['societyRole']?.toString();

      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: societyId,
        systemRole: systemRole,
        name: name,
      );

      if (systemRole == 'guard') {
        await Storage.saveGuardSession(
          guardId: uid,
          guardName: name.isNotEmpty ? name : 'Guard',
          societyId: societyId,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GuardShellScreen(
              guardId: uid,
              guardName: name.isNotEmpty ? name : 'Guard',
              societyId: societyId,
            ),
          ),
        );
        return;
      }
      if (systemRole == 'resident' && flatNo != null && flatNo.isNotEmpty) {
        await Storage.saveResidentSession(
          residentId: uid,
          residentName: name.isNotEmpty ? name : 'Resident',
          societyId: societyId,
          flatNo: flatNo,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResidentShellScreen(
              residentId: uid,
              residentName: name.isNotEmpty ? name : 'Resident',
              societyId: societyId,
              flatNo: flatNo,
            ),
          ),
        );
        return;
      }
      if (systemRole == 'admin' || systemRole == 'super_admin') {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminShellScreen(
              adminId: uid,
              adminName: name.isNotEmpty ? name : 'Admin',
              societyId: societyId,
              role: societyRole ?? 'ADMIN',
            ),
          ),
        );
        return;
      }

      setState(() => _isLoading = false);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyOtpError(e.code);
      });
    } catch (e, st) {
      AppLogger.e('Phone OTP verify failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Verification failed. Try again.';
      });
    }
  }

  void _showNoAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No account found'),
        content: const Text(
          'This number is not linked to any account. Sign up as Guard, Resident, or Admin to get started.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              FirebaseAuth.instance.signOut();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (_) => const OnboardingChooseRoleScreen()),
              );
            },
            child: const Text('Sign up'),
          ),
        ],
      ),
    );
  }

  static String _friendlyPhoneError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid phone number. Use 10 digits.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'quota-exceeded':
        return 'Too many OTPs. Try again later.';
      default:
        return 'Could not send OTP. Check number and try again.';
    }
  }

  static String _friendlyOtpError(String code) {
    switch (code) {
      case 'invalid-verification-code':
        return 'Invalid OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'invalid-verification-id':
        return 'Session expired. Please start again.';
      default:
        return 'Verification failed. Try again.';
    }
  }

  // =========================
  // UI (modern 2026 look)
  // =========================

  String get _roleTitle {
    final r = (widget.roleHint ?? 'resident').toLowerCase();
    if (r == 'guard') return 'Guard Login';
    if (r == 'admin') return 'Admin Login';
    return 'Welcome 👋';
  }

  String get _roleSubtitle {
    final r = (widget.roleHint ?? 'resident').toLowerCase();
    if (r == 'guard') return 'Enter your mobile number to continue';
    if (r == 'admin') return 'Enter your mobile number to continue';
    return 'Enter your mobile number to continue';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF6F2FF), // soft lavender like reference
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_codeSent) {
              setState(() {
                _codeSent = false;
                _verificationId = null;
                _errorMessage = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    const SizedBox(height: 18),

                    // Top illustration area (optional but recommended)
                    SizedBox(
                      height: 140,
                      child: Image.asset(
                        'assets/illustrations/illustration_login_resident.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.phone_iphone_rounded,
                          size: 64,
                          color: AppColors.primary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Center card (this is the main “2026” look)
                    _AuthCard(
                      child:
                          _codeSent ? _otpCardContent() : _phoneCardContent(),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _phoneCardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Login with\nmobile number",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.15,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "We’ll send you a one-time password (OTP).",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 18),

        // Phone input row (like reference)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🇮🇳', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text(
                    '+91',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Enter mobile number',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.4),
                  ),
                ),
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
            ),
          ],
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],

        const SizedBox(height: 18),

        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _sendOtp,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black, // like reference
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('CONTINUE',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 14),

        Text(
          "By continuing, you agree to our Terms & Privacy Policy.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text2.withOpacity(0.85),
          ),
        ),
      ],
    );
  }

  Widget _otpCardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Verify Phone",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Code sent to +91 ${_phoneController.text.trim()}",
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 10,
            fontWeight: FontWeight.w900,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
          onChanged: (_) => setState(() => _errorMessage = null),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _sendOtp,
            child: const Text(
              "Resend OTP",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('VERIFY',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildIllustrationHero() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Your illustration (kept same asset)
        SizedBox(
          height: 200,
          child: Image.asset(
            'assets/illustrations/illustration_login_resident.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(
                child: Icon(
                  Icons.home_rounded,
                  size: 72,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _roleTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _roleSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.text2,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneStepModern() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const Text(
          'Mobile Number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _CountryPill(disabled: _isLoading),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: '10-digit mobile number',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: AppColors.primary.withOpacity(0.9), width: 1.3),
                  ),
                ),
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _InlineError(message: _errorMessage!),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _isLoading ? null : _sendOtp,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Built with ❤️ in Rajasthan, India',
            style: TextStyle(
              color: AppColors.text2.withOpacity(0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStepModern() {
    final masked = _maskPhone(_phoneController.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 2),

        const Text(
          'Verify OTP',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sent to +91 $masked',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.text2,
          ),
        ),

        const SizedBox(height: 18),

        // Keep your existing single field OTP (logic unchanged),
        // but style it like a modern OTP input.
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !_isLoading,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            letterSpacing: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
          decoration: InputDecoration(
            hintText: '••••••',
            counterText: '',
            filled: true,
            fillColor: const Color(0xFFF6F8FF),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                  color: AppColors.primary.withOpacity(0.9), width: 1.3),
            ),
          ),
          onChanged: (_) => setState(() => _errorMessage = null),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _InlineError(message: _errorMessage!),
        ],

        const SizedBox(height: 10),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _sendOtp,
            child: const Text(
              'Resend OTP',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),

        const SizedBox(height: 6),

        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Verify & Continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ],
    );
  }

  String _maskPhone(String phone10) {
    if (phone10.length < 10) return phone10;
    final last2 = phone10.substring(phone10.length - 2);
    return 'XXXXXXXX$last2';
  }
}

class _BottomSheetCard extends StatelessWidget {
  final Widget child;
  const _BottomSheetCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CountryPill extends StatelessWidget {
  final bool disabled;
  const _CountryPill({required this.disabled});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🇮🇳', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text(
              '+91',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _SoftBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size),
      ),
    );
  }
}
