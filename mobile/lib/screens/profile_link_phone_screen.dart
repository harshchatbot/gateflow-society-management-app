import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';

/// Profile: link phone to current Firebase user (e.g. email-only user adding phone).
/// Enforces unique phone; saves to member doc and unique_phones.
class ProfileLinkPhoneScreen extends StatefulWidget {
  final String societyId;
  final String uid;

  const ProfileLinkPhoneScreen({
    super.key,
    required this.societyId,
    required this.uid,
  });

  @override
  State<ProfileLinkPhoneScreen> createState() => _ProfileLinkPhoneScreenState();
}

class _ProfileLinkPhoneScreenState extends State<ProfileLinkPhoneScreen> {
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
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final available = await _firestore.isPhoneAvailableForUser(
        normalizedE164: phone,
        forUid: widget.uid,
      );
      if (!mounted) return;
      if (!available) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'This number is already linked to another account.';
        });
        return;
      }
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
        _errorMessage = _friendlyError(e.code);
      });
    } catch (e, st) {
      AppLogger.e('Profile link phone: send OTP failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not send OTP. Try again.';
      });
    }
  }

  Future<void> _verifyAndLink() async {
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
      await _authService.linkWithPhoneCredential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _firestore.setMemberPhone(
        societyId: widget.societyId,
        uid: widget.uid,
        normalizedE164: _normalizedPhone,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number added successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyError(e.code);
      });
    } catch (e, st) {
      AppLogger.e('Profile link phone: verify failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Verification failed. Try again.';
      });
    }
  }

  static String _friendlyError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid phone number.';
      case 'invalid-verification-code':
        return 'Invalid OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'credential-already-in-use':
        return 'This number is already linked to another account.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return 'Something went wrong. Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add phone number'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _codeSent ? _buildOtpStep() : _buildPhoneStep(),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Add your mobile number for easier login',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.text2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  '+91',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: InputDecoration(
                    hintText: '10-digit number',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: AppColors.bg,
                  ),
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _sendOtp,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            'Enter the 6-digit code sent to +91 ${_phoneController.text.trim()}',
            style: const TextStyle(fontSize: 14, color: AppColors.text2),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: AppColors.bg,
            ),
            onChanged: (_) => setState(() => _errorMessage = null),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
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
              onPressed: _isLoading ? null : _verifyAndLink,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify & Add'),
            ),
          ),
        ],
      ),
    );
  }
}
