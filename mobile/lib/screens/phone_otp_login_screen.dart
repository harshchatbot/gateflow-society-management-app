import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../core/session_gate_service.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import 'admin_onboarding_screen.dart';
import 'admin_pending_approval_screen.dart';
import 'admin_shell_screen.dart';
import 'admin_signup_screen.dart';
import 'find_society_screen.dart';
import 'guard_join_screen.dart';
import 'guard_shell_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'platform_super_admin_console_screen.dart';
import 'resident_pending_approval_screen.dart';
import 'resident_shell_screen.dart';

enum _OtpStep { phone, otp }

/// Unified Phone OTP login (primary auth).
/// Same screen for Guard/Resident/Admin. UI varies by roleHint, routing uses membership.
class PhoneOtpLoginScreen extends StatefulWidget {
  /// Optional: guard | resident | admin — for UI only (authority is membership).
  final String? roleHint;

  const PhoneOtpLoginScreen({super.key, this.roleHint});

  @override
  State<PhoneOtpLoginScreen> createState() => _PhoneOtpLoginScreenState();
}

class _PhoneOtpLoginScreenState extends State<PhoneOtpLoginScreen> {
  final _formKeyPhone = GlobalKey<FormState>();
  final _formKeyOtp = GlobalKey<FormState>();

  final _authService = FirebaseAuthService();
  final _firestore = FirestoreService();

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _isLoading = false;

  _OtpStep _step = _OtpStep.phone;

  String? _verificationId;
  int? _resendToken;

  int _resendSeconds = 0;
  Timer? _resendTimer;

  bool get _canResend => _resendSeconds <= 0 && !_isLoading;

  bool get _isAdminHint => (widget.roleHint ?? '').toLowerCase() == 'admin';
  bool get _isGuardHint => (widget.roleHint ?? '').toLowerCase() == 'guard';

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

  String _maskPhoneE164(String phoneE164) {
    // +91xxxxxxxxxx -> +91******xxxx
    if (phoneE164.length <= 6) return phoneE164;
    final last4 = phoneE164.substring(phoneE164.length - 4);
    return '${phoneE164.substring(0, 3)}******$last4';
  }

  String get _normalizedPhone =>
      FirebaseAuthService.normalizePhoneForIndia(_phoneController.text.trim());

  Future<Map<String, dynamic>?> _getMembershipOrRecover({
    required String uid,
    required String normalizedPhone,
  }) async {
    // 1) Try normal membership
    final m1 = await _firestore.getCurrentUserMembership();
    if (m1 != null) return m1;

    // 2) Try phone_index recovery
    try {
      final idx = await _firestore.getPhoneIndex(normalizedPhone);
      if (idx == null) return null;

      final idxUid = idx['uid']?.toString();
      if (idxUid != null && idxUid.isNotEmpty && idxUid != uid) {
        AppLogger.w("phone_index uid mismatch",
            data: {"authUid": uid, "idxUid": idxUid});
        return null;
      }

      final societyId = idx['societyId']?.toString() ?? '';
      final systemRole = idx['systemRole']?.toString() ?? '';
      if (societyId.isEmpty || systemRole.isEmpty) return null;

      await _firestore.ensureRootMemberPointer(
        uid: uid,
        societyId: societyId,
        systemRole: systemRole,
        active: idx['active'] == true,
      );

      final m2 = await _firestore.getCurrentUserMembership();
      return m2;
    } catch (e, st) {
      AppLogger.e("phone_index recovery failed", error: e, stackTrace: st);
      return null;
    }
  }

  Future<void> _sendOtp({bool forceResend = false}) async {
    if (_isLoading) return;
    if (!_formKeyPhone.currentState!.validate()) return;

    final raw = _phoneController.text.trim();
    final normalized = FirebaseAuthService.normalizePhoneForIndia(raw);

    setState(() => _isLoading = true);

    try {
      AppLogger.i("OTP: sending code", data: {
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

      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) FocusScope.of(context).requestFocus(_otpFocus);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("OTP sent to ${_maskPhoneE164(normalized)}"),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } on FirebaseAuthException catch (e, st) {
      AppLogger.e("OTP send failed", error: e, stackTrace: st);

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
      AppLogger.e("OTP send unknown error", error: e, stackTrace: st);
      _showError("Failed to send OTP. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtpAndRoute() async {
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
      AppLogger.i("OTP: verifying code");

      final cred = await _authService.signInWithPhoneCredential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final uid = cred.user?.uid;
      if (uid == null) throw Exception("Failed to authenticate");

      // ✅ membership OR recovery via phone_index
      final membership = await _getMembershipOrRecover(
        uid: uid,
        normalizedPhone: _normalizedPhone,
      );

      // 🚫 No membership → onboarding by roleHint (UI only)
      // 🚫 No membership → could be NEW user OR pending join request
      // 🚫 No membership → could be NEW user OR pending join request
      if (membership == null) {
        AppLogger.w("No membership → checking pending join_requests", data: {
          'uid': uid,
          'roleHint': widget.roleHint,
        });

        // 🔍 STEP-1: lookup pending join request
        try {
          AppLogger.i("JoinRequest lookup: start", data: {'uid': uid});

          Map<String, dynamic>? jr;

          final roleHint = (widget.roleHint ?? '').trim().toLowerCase();

          // ✅ RESIDENT ONLY: use join_request_index/{uid} (GET, no query)

          if (roleHint == 'resident') {
            try {
              AppLogger.i("Resident JoinRequestIndex: start",
                  data: {'uid': uid});

              final idx = await _firestore.getJoinRequestIndex(uid);

              AppLogger.i("Resident JoinRequestIndex: result", data: {
                'found': idx != null,
                'status': idx?['status'],
                'societyId': idx?['societyId'],
                'requestedRole': idx?['requestedRole'],
              });

              if (idx != null) {
                final status = (idx['status'] ?? '').toString().toUpperCase();
                final requestedRole = (idx['requestedRole'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final societyIdFromIdx =
                    (idx['societyId'] ?? '').toString().trim();
                final nameFromIdx = (idx['name'] ?? '').toString().trim();
                final phoneFromIdx = (idx['phone'] ?? '').toString().trim();

                if (requestedRole == 'resident' &&
                    status == 'PENDING' &&
                    societyIdFromIdx.isNotEmpty) {
                  if (!mounted) return;

                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ResidentPendingApprovalScreen(
                        residentId: uid,
                        societyId: societyIdFromIdx,
                        residentName:
                            nameFromIdx.isNotEmpty ? nameFromIdx : 'Resident',
                        email: phoneFromIdx.isNotEmpty
                            ? phoneFromIdx
                            : _normalizedPhone,
                      ),
                    ),
                  );
                  return; // ✅ STOP: do not fall back to FindSociety
                }

                if (requestedRole == 'resident' &&
                    status == 'REJECTED' &&
                    societyIdFromIdx.isNotEmpty) {
                  // optional cleanup if you want
                  await Storage.clearResidentJoinSocietyId();
                }
              }
            } catch (e, st) {
              AppLogger.e("Resident JoinRequestIndex failed",
                  error: e, stackTrace: st);
            }
          }

  
        } catch (e, st) {
          AppLogger.e("JoinRequest lookup failed", error: e, stackTrace: st);
        }

        AppLogger.e("RESIDENT FALLBACK HIT", data: {
          'uid': uid,
          'normalizedPhone': _normalizedPhone,
        });

        // ⬇️ FALLBACK (existing behavior)
        if (!mounted) return;
        setState(() => _isLoading = false);

        final role = (widget.roleHint ?? 'resident').trim().toLowerCase();

        if (role == 'admin') {
          final pendingSocietyRequest =
              await _firestore.getPendingSocietyCreationRequestForUser(uid: uid);
          if (pendingSocietyRequest != null) {
            final requestedSocietyId =
                (pendingSocietyRequest['proposedSocietyId'] ?? '')
                    .toString()
                    .trim();
            final requestedSocietyName =
                (pendingSocietyRequest['proposedName'] ?? '')
                    .toString()
                    .trim();
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => AdminPendingApprovalScreen(
                  adminId: uid,
                  societyId: requestedSocietyId.isNotEmpty
                      ? requestedSocietyId
                      : 'pending_society',
                  adminName:
                      (pendingSocietyRequest['requesterName'] ?? '').toString(),
                  email: (pendingSocietyRequest['requesterPhone'] ??
                          _normalizedPhone)
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

          final pointer = await _firestore.getRootMemberPointer(uid: uid);
          final pointerRole =
              (pointer?['systemRole'] ?? '').toString().toLowerCase();
          final pointerActive = pointer?['active'] == true;
          final pointerSocietyId =
              (pointer?['societyId'] ?? '').toString().trim();

          if (pointerRole == 'admin' &&
              !pointerActive &&
              pointerSocietyId.isNotEmpty) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => AdminPendingApprovalScreen(
                  adminId: uid,
                  societyId: pointerSocietyId,
                  adminName: (pointer?['name'] ?? 'Admin').toString(),
                  email: (pointer?['phone'] ?? _normalizedPhone).toString(),
                ),
              ),
            );
            return;
          }

          if (pointerRole == 'super_admin' && pointerActive) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => PlatformSuperAdminConsoleScreen(
                  adminName: (pointer?['name'] ?? 'Platform Admin').toString(),
                ),
              ),
            );
            return;
          }

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const FindSocietyScreen(mode: 'admin')),
          );
          return;
        }

        if (role == 'guard') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const GuardJoinScreen()),
          );
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => const FindSocietyScreen(mode: 'resident')),
        );
        return;
      }

      final societyId = membership['societyId']?.toString() ?? '';
      final systemRole =
          (membership['systemRole']?.toString() ?? '').toLowerCase();
      final name = membership['name']?.toString() ?? '';
      final flatNo = membership['flatNo']?.toString();
      final societyRole = membership['societyRole']?.toString();
      final active = membership['active'] == true;

      if (systemRole != 'super_admin') {
        // 🔒 Gate inactive societies
        final gate = SessionGateService();
        final gateResult = await gate.validateSessionAfterLogin(uid);
        if (!mounted) return;
        if (!gateResult.allowed) {
          await FirebaseAuth.instance.signOut();
          await Storage.clearFirebaseSession();
          await Storage.clearAllSessions();

          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
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
      }

      // ✅ Save unified session
      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: (systemRole == 'super_admin' && societyId.trim().isEmpty)
            ? 'platform'
            : societyId,
        systemRole: systemRole,
        societyRole: societyRole,
        name: name,
      );

      // ✅ SUPER ADMIN goes to dedicated platform console
      if (systemRole == 'super_admin') {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PlatformSuperAdminConsoleScreen(
              adminName: name.isNotEmpty ? name : 'Platform Admin',
            ),
          ),
        );
        return;
      }

      // ✅ Admin pending approval
      if (systemRole == 'admin' && !active) {
        if (!mounted) return;
        final contact =
            FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ??
                FirebaseAuth.instance.currentUser?.email?.trim() ??
                '';
        Navigator.of(context).pushReplacement(
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

      // ✅ Resident pending approval
      if (systemRole == 'resident' && !active) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResidentPendingApprovalScreen(
              residentId: uid,
              societyId: societyId,
              residentName: name.isNotEmpty ? name : 'Resident',
            ),
          ),
        );
        return;
      }

      // ✅ Normal routing
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

      if (systemRole == 'admin') {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminShellScreen(
              adminId: uid,
              adminName: name.isNotEmpty ? name : 'Admin',
              societyId: societyId,
              role: (societyRole ?? 'ADMIN').toUpperCase(),
              systemRole: systemRole,
            ),
          ),
        );
        return;
      }

      // fallback
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      );

      // Ensure phone is saved on member (best effort)
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
            // non-fatal
          }
        }
      }
    } on FirebaseAuthException catch (e, st) {
      AppLogger.e("OTP verify failed", error: e, stackTrace: st);

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

      if (code == 'session-expired' || code.contains('session-expired')) {
        setState(() {
          _step = _OtpStep.phone;
          _verificationId = null;
          _otpController.clear();
        });
      }
    } catch (e, st) {
      AppLogger.e("OTP verify unknown error", error: e, stackTrace: st);
      if (!mounted) return;
      _showError("Login failed. Please try again.");
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
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

  Future<Map<String, dynamic>?> getJoinRequestIndex(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('join_request_index')
        .doc(uid)
        .get();

    if (!doc.exists) return null;
    return Map<String, dynamic>.from(doc.data() as Map);
  }

  Future<void> upsertJoinRequestIndex({
    required String uid,
    required String societyId,
    required String requestedRole,
    required String status,
    String? name,
    String? phone,
  }) async {
    await FirebaseFirestore.instance
        .collection('join_request_index')
        .doc(uid)
        .set({
      'uid': uid,
      'societyId': societyId,
      'requestedRole': requestedRole.toLowerCase(),
      'status': status.toUpperCase(),
      'name': (name ?? '').trim(),
      'phone': (phone ?? '').trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

  // =========================
  // UI (AdminLoginScreen look & feel)
  // =========================

  String get _heroTitle {
    final r = (widget.roleHint ?? 'resident').toLowerCase();
    if (r == 'admin') return "Admin Portal";
    if (r == 'guard') return "Guard Portal";
    return "Resident Portal";
  }

  String get _heroSubtitle {
    return _step == _OtpStep.phone
        ? "Login using your phone number"
        : "Enter the OTP sent to your phone";
  }

  String get _heroAsset {
    final r = (widget.roleHint ?? 'resident').toLowerCase();
    if (r == 'admin')
      return 'assets/illustrations/illustration_login_admin.png';
    if (r == 'guard') return 'assets/illustrations/guard_login.png';
    return 'assets/illustrations/illustration_society_11.png';
  }

  IconData get _heroFallbackIcon {
    final r = (widget.roleHint ?? 'resident').toLowerCase();
    if (r == 'admin') return Icons.admin_panel_settings_rounded;
    if (r == 'guard') return Icons.shield_rounded;
    return Icons.home_rounded;
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
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
            if (_step == _OtpStep.otp) {
              setState(() {
                _step = _OtpStep.phone;
                _verificationId = null;
                _otpController.clear();
              });
              FocusScope.of(context).requestFocus(_phoneFocus);
              return;
            }

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
          // Calm background wash (same vibe as AdminLoginScreen)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withOpacity(0.12),
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

                  // ✅ ONLY Admin sees Create Society CTA (and ONLY on phone step)
                  if (_isAdminHint && _step == _OtpStep.phone) ...[
                    _buildCreateSocietyCta(context),
                    const SizedBox(height: 24),
                  ] else ...[
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),

          // Simple overlay loader
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.08),
                child: const Center(
                  child: SizedBox(
                    height: 34,
                    width: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            ),
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
            _heroAsset,
            fit: BoxFit.contain,
            errorBuilder: (ctx, __, ___) => Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                _heroFallbackIcon,
                size: 64,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _heroTitle,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _heroSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withOpacity(0.18)),
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
          border: Border.all(color: AppColors.border.withOpacity(0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
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
                        color: cs.onSurface.withOpacity(0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PremiumField(
                      controller: _phoneController,
                      focusNode: _phoneFocus,
                      hint: "e.g. 9876543210",
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _sendOtp(),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return "Please enter your phone";
                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                        if (digits.length != 10)
                          return "Enter a valid 10-digit number";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _sendOtp(),
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
                        color: cs.onSurface.withOpacity(0.65),
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
                        color: cs.onSurface.withOpacity(0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PremiumField(
                      controller: _otpController,
                      focusNode: _otpFocus,
                      hint: "Enter 6-digit OTP",
                      icon: Icons.password_rounded,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verifyOtpAndRoute(),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return "Please enter OTP";
                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                        if (digits.length != 6)
                          return "Enter a valid 6-digit OTP";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOtpAndRoute,
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
                          "VERIFY & CONTINUE",
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
                                  : cs.onSurface.withOpacity(0.45),
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
        color: cs.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.14),
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
                  "Request Society Admin setup",
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.7),
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
                        builder: (_) => const AdminOnboardingScreen(),
                      ),
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
  final String hint;
  final IconData icon;

  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;

  const _PremiumField({
    required this.controller,
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
            color: Colors.black.withOpacity(0.02),
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
              color: cs.primary.withOpacity(0.15),
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
