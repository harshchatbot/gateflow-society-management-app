import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../core/session_gate_service.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import 'admin_shell_screen.dart';
import 'admin_signup_screen.dart';
import 'find_society_screen.dart';
import 'guard_join_screen.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'resident_shell_screen.dart';
import 'resident_signup_screen.dart';

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
                MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _codeSent ? _buildOtpStep() : _buildPhoneStep(),
        ),
      ),
    );
  }

  /// Illustration banner reused from resident login screen.
  Widget _buildBrandHeader() {
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 160,
          child: Image.asset(
            'assets/illustrations/illustration_login_resident.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.home_rounded,
                size: 64,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Resident Login",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Secure Society Access",
          style: TextStyle(
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          _buildBrandHeader(),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇮🇳', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      '+91',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
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
                    hintText: 'Mobile number',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _sendOtp,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send OTP'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            'Enter OTP',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit code to +91 ${_phoneController.text.trim()}',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: AppColors.bg,
            ),
            onChanged: (_) => setState(() => _errorMessage = null),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isLoading ? null : _sendOtp,
            child: const Text('Resend OTP'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _verifyOtp,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify & Continue'),
            ),
          ),
        ],
      ),
    );
  }
}
