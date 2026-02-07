import 'dart:async';

import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_logger.dart';
import '../core/env.dart';
import '../core/storage.dart';
import '../services/admin_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../services/invite_claim_service.dart';
import '../services/invite_bulk_upload_service.dart';
import '../ui/app_loader.dart';
import 'admin_shell_screen.dart';
import 'admin_login_screen.dart';
import 'admin_pending_approval_screen.dart';

/// Admin Onboarding Screen
///
/// CREATE SOCIETY: OTP-first (Send OTP on Submit -> Verify -> Create society+member+phone_index+root pointer)
/// JOIN SOCIETY: kept as existing email/pin flow (to avoid breaking invite-claim logic)
class AdminOnboardingScreen extends StatefulWidget {
  final bool defaultJoinMode;
  const AdminOnboardingScreen({super.key, this.defaultJoinMode = false});

  @override
  State<AdminOnboardingScreen> createState() => _AdminOnboardingScreenState();
}

class _AdminOnboardingScreenState extends State<AdminOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _societyCodeController = TextEditingController();
  final _societyNameController = TextEditingController();
  String? _selectedCity;
  String? _selectedState;
  final _adminIdController = TextEditingController(); // Email (profile/claim)
  final _adminNameController = TextEditingController();
  final _phoneController =
      TextEditingController(); // REQUIRED for OTP create-society
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  late final AdminService _adminService = AdminService(
    baseUrl: Env.apiBaseUrl,
  );

  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();
  final InviteClaimService _inviteClaimService = InviteClaimService();

  bool _isLoading = false;
  bool _isLoadingLocations = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isCreatingSociety = true;
  String _selectedRole = "SUPER_ADMIN";

  late ConfettiController _confettiController;

  // Dynamic state & city lists loaded from Firestore
  List<Map<String, String>> _stateOptions = [];
  List<Map<String, String>> _cityOptions = [];
  String? _selectedStateId;

  final List<String> _roles = [
    "SUPER_ADMIN",
    "ADMIN",
    "PRESIDENT",
    "SECRETARY",
    "TREASURER",
    "COMMITTEE",
  ];

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    _isCreatingSociety = !widget.defaultJoinMode; // ✅ key line
    _selectedRole = _isCreatingSociety ? "SUPER_ADMIN" : "ADMIN";
    _loadStates();
  }

  Future<void> _loadStates() async {
    setState(() {
      _isLoadingLocations = true;
      _stateOptions = [];
      _cityOptions = [];
      _selectedStateId = null;
      _selectedState = null;
      _selectedCity = null;
    });

    final states = await _firestore.getStatesList();

    setState(() {
      _stateOptions = states;
      _isLoadingLocations = false;
    });
  }

  Future<void> _loadCitiesForState(String stateId) async {
    setState(() {
      _isLoadingLocations = true;
      _cityOptions = [];
      _selectedCity = null;
    });

    final cities = await _firestore.getCitiesForState(stateId);

    setState(() {
      _cityOptions = cities;
      _isLoadingLocations = false;
    });
  }

  @override
  void dispose() {
    _societyCodeController.dispose();
    _societyNameController.dispose();
    _adminIdController.dispose();
    _adminNameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ✅ helper: create root pointer /members/{uid}
  Future<void> _setRootPointer({
    required String uid,
    required String societyId,
    required String systemRole,
    required bool active,
  }) async {
    await FirebaseFirestore.instance.collection('members').doc(uid).set({
      'uid': uid,
      'societyId': societyId,
      'systemRole': systemRole,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ✅ OTP-first on submit for CREATE SOCIETY.
  Future<_OtpAuthResult?> _verifyPhoneViaOtpAndGetAuth(String rawPhone) async {
    final digits = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length != 10) {
      _showError("Enter a valid 10-digit mobile number.");
      return null;
    }

    final phoneE164 = FirebaseAuthService.normalizePhoneForIndia(digits);

    final result = await Navigator.of(context).push<_OtpAuthResult>(
      MaterialPageRoute(
        builder: (_) => OtpVerifyScreen(phoneE164: phoneE164),
      ),
    );

    return result; // null if cancelled
  }

  /// Normalize typed phone to E.164 (+91...) if user entered 10 digits
  String _normalizeTypedPhoneToE164(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('+')) return v;
    final digits = v.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 10) {
      return FirebaseAuthService.normalizePhoneForIndia(digits);
    }
    return v; // keep as-is; caller can decide if acceptable
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final societyCode = _societyCodeController.text.trim().toUpperCase();
    final adminName = _adminNameController.text.trim();
    final email = _adminIdController.text.trim();
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim(); // used only for JOIN flow below

    setState(() => _isLoading = true);

    AppLogger.i("Admin onboarding attempt", data: {
      "society_code": societyCode,
      "email": email,
      "mode": _isCreatingSociety ? "create(otp)" : "join(email/pin)",
      "role": _selectedRole,
    });

    try {
      // Step A: Authenticate
      String uid;
      String authPhoneE164 = '';

      if (_isCreatingSociety) {
        // ✅ OTP FIRST
        final otp = await _verifyPhoneViaOtpAndGetAuth(phone);
        if (otp == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        uid = otp.uid;
        authPhoneE164 = otp.authPhone;
      } else {
        // ✅ Join flow is email/pin (legacy) to preserve InviteClaimService behavior.
        final userCredential = await _authService.signUpOrSignIn(
          email: email,
          password: pin,
        );

        final u = userCredential.user;
        if (u == null) throw Exception("Failed to authenticate");
        uid = u.uid;

        // ✅ Do NOT require OTP here.
        // Prefer FirebaseAuth phoneNumber if present, else use typed phone (optional), else empty.
        final tokenPhone = u.phoneNumber;
        if (tokenPhone != null && tokenPhone.trim().isNotEmpty) {
          authPhoneE164 = _normalizeTypedPhoneToE164(tokenPhone);
        } else {
          authPhoneE164 = _normalizeTypedPhoneToE164(phone);
        }
      }

      // Optional: enforce unique phone only if we have a valid E.164-ish phone
      if (authPhoneE164.isNotEmpty && authPhoneE164.startsWith('+')) {
        final ok = await _firestore.isPhoneAvailableForUser(
          normalizedE164: authPhoneE164,
          forUid: uid,
        );
        if (!ok) {
          if (mounted) setState(() => _isLoading = false);
          _showError(
              "This mobile number is already linked to another active account.");
          return;
        }
      }

      // Step B: Resolve or create society
      String societyId;

      if (_isCreatingSociety) {
        // CREATE SOCIETY = SUPER_ADMIN bootstrap (after OTP verify)
        final societyName = _societyNameController.text.trim();
        final city = _selectedCity;
        final state = _selectedState;

        // Prevent duplicate society code reuse
        final existing = await _firestore.getSocietyIdByCode(societyCode);
        if (existing != null) {
          if (mounted) setState(() => _isLoading = false);
          _showError("Society code already exists. Choose a different code.");
          return;
        }

        societyId = 'soc_${societyCode.toLowerCase()}';

        await _firestore.createSociety(
          societyId: societyId,
          code: societyCode,
          name: societyName,
          city: city,
          state: state,
          createdByUid: uid,
        );

        // ✅ Create super admin member record with VERIFIED PHONE (authPhoneE164)
        await _firestore.setMember(
          societyId: societyId,
          uid: uid,
          systemRole: 'super_admin',
          societyRole: _selectedRole.toLowerCase(),
          name: adminName,
          phone: authPhoneE164,
          email: email,
          active: true,
        );

        // ✅ Keep your legacy phone_index (safe)
        if (authPhoneE164.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('phone_index')
              .doc(authPhoneE164)
              .set({
            'uid': uid,
            'societyId': societyId,
            'systemRole': 'super_admin',
            'active': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // ✅ IMPORTANT: populate unique_phones (your real uniqueness system)
          // Writes member phone + pointer phone + unique_phones hash doc
          await _firestore.setMemberPhone(
            societyId: societyId,
            uid: uid,
            normalizedE164: authPhoneE164,
          );
        }

        await _setRootPointer(
          uid: uid,
          societyId: societyId,
          systemRole: 'super_admin',
          active: true,
        );

        // =========================================================
// ✅ Publish society to public directory (SUPER_ADMIN only)
// =========================================================
        final now = FieldValue.serverTimestamp();
        final normalizedCode = societyCode.trim().toUpperCase();

        final publicSocietyData = {
          'name': societyName,
          'nameLower': societyName.toLowerCase(),
          'code': normalizedCode,
          'city': _selectedCity,
          'state': _selectedState,
          'active': true,
          'createdAt': now,
          'updatedAt': now,
          'createdByUid': uid,
        };

        AppLogger.i('Publishing public_societies entry',
            data: {'path': 'public_societies/$societyId'});

        await FirebaseFirestore.instance
            .collection('public_societies')
            .doc(societyId)
            .set(publicSocietyData);

        _confettiController.play();
        await Future.delayed(const Duration(milliseconds: 1200));
      } else {
        // ✅ JOIN SOCIETY: Admin requests access -> Pending approval
        final existingSocietyId =
            await _firestore.getSocietyIdByCode(societyCode);
        if (existingSocietyId == null) {
          if (mounted) setState(() => _isLoading = false);
          _showError("Society not found or inactive for this code.");
          return;
        }
        societyId = existingSocietyId;

        // ✅ Create (or overwrite) admin join request
        final payload = <String, dynamic>{
          'uid': uid,
          'societyId': societyId,
          'name': adminName,
          'email': email,
          'societyRole': _selectedRole.toLowerCase(),
          'status': 'PENDING',
          'active': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (authPhoneE164.isNotEmpty) {
          payload['phone'] = authPhoneE164;
        }

        await FirebaseFirestore.instance
            .collection('societies')
            .doc(societyId)
            .collection('admin_join_requests')
            .doc(uid)
            .set(payload, SetOptions(merge: true));

        // ✅ Create/ensure root pointer (inactive) so app can resolve society quickly
        await _setRootPointer(
          uid: uid,
          societyId: societyId,
          systemRole: 'admin',
          active: false,
        );

        // ✅ OPTIONAL: phone_index pointer (helps recovery / faster mapping)
        if (authPhoneE164.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('phone_index')
              .doc(authPhoneE164)
              .set({
            'uid': uid,
            'societyId': societyId,
            'systemRole': 'admin',
            'active': false,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        if (!mounted) return;
        if (mounted) setState(() => _isLoading = false);

        // ✅ Go to pending approval (super admin will approve)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminPendingApprovalScreen(
              adminId: uid,
              societyId: societyId,
              adminName: adminName.isNotEmpty ? adminName : 'Admin',
              email: authPhoneE164.isNotEmpty ? authPhoneE164 : email,
            ),
          ),
        );
        return;
      }

      // Step C: Save Firebase session
      final systemRoleForSession = _isCreatingSociety ? 'super_admin' : 'admin';

      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: societyId,
        systemRole: systemRoleForSession,
        societyRole: _selectedRole,
        name: adminName,
      );

      AppLogger.i("Admin onboarding successful", data: {
        'uid': uid,
        'societyId': societyId,
        'systemRole': systemRoleForSession,
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.onPrimary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Account created successfully!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminShellScreen(
            adminId: uid,
            adminName: adminName,
            societyId: societyId,
            role: _selectedRole,
            systemRole: systemRoleForSession,
          ),
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.e("Admin onboarding exception",
          error: e, stackTrace: stackTrace);

      if (!mounted) return;
      setState(() => _isLoading = false);

      final err = e.toString();

      // ✅ Frontend-friendly: Society already exists
      if (err.contains('SOCIETY_ALREADY_EXISTS:SOCIETY_CODE')) {
        _showError("Society code already exists. Choose a different code.");
        return;
      }

      if (err.contains('SOCIETY_ALREADY_EXISTS')) {
        _showError(
            "Society is already registered. Please try a different code/name.");
        return;
      }

      // Optional tells you it's permission issue (still user-friendly)
      if (err.contains('permission-denied')) {
        _showError(
            "You don’t have permission to create this society. Please contact support.");
        return;
      }

      // Fallback (your current behavior)
      _showError("Registration failed. Please try again.");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
              size: 20,
            ),
          ),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.15),
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildBrandHeader(),
                  const SizedBox(height: 40),
                  _buildRegistrationForm(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          if (_isLoading || _isLoadingLocations)
            AppLoader.overlay(showAfter: const Duration(milliseconds: 300), 
              show: true,
              message: _isLoading
                  ? (_isCreatingSociety
                      ? "Verifying OTP & creating society…"
                      : "Creating your account…")
                  : "Loading locations…",
            ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 25,
              maxBlastForce: 18,
              minBlastForce: 5,
              gravity: 0.25,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.tertiary,
                theme.colorScheme.secondary,
                theme.colorScheme.primary.withOpacity(0.8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          width: 220,
          height: 160,
          child: Image.asset(
            'assets/illustrations/society.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                _isCreatingSociety
                    ? Icons.groups_rounded
                    : Icons.person_add_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isCreatingSociety ? "Create New Society" : "Join Society",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _isCreatingSociety
              ? "Set up your society and become super admin"
              : "Claim your admin invite to join",
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _uploadInvitesCsv({
    required String societyId,
  }) async {
    try {
      setState(() => _isLoading = true);

      final result = await InviteBulkUploadService().pickCsvAndUploadInvites(
        societyId: societyId,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      final msg =
          "Processed: ${result.processed} | Created: ${result.created} | Skipped: ${result.skipped}";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );

      if (result.errors.isNotEmpty) {
        AppLogger.w("Bulk invite upload errors",
            data: {"errors": result.errors});
      }
    } catch (e, st) {
      AppLogger.e("Bulk invite upload failed", error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError("Upload failed: ${e.toString()}");
    }
  }

  Widget _buildRegistrationForm() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Fill in your details",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.apartment_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isCreatingSociety
                          ? "Create society mode"
                          : "Join society mode",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_isCreatingSociety) ...[
              _PremiumField(
                controller: _societyNameController,
                label: "Society Name",
                hint: "e.g. Kedia Amara",
                icon: Icons.location_city_rounded,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter Society Name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.9)),
                ),
                child: Column(
                  children: [
                    _buildStateDropdown(theme),
                    const SizedBox(height: 12),
                    _buildCityDropdown(theme),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            _PremiumField(
              controller: _societyCodeController,
              label: "Society Code",
              hint: "e.g. SSRESIDENCY (unique)",
              icon: Icons.apartment_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter Society Code";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _adminIdController,
              label: "Email Address",
              hint: "e.g. admin@example.com",
              icon: Icons.email_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your email";
                }
                if (!value.contains('@')) {
                  return "Please enter a valid email";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _adminNameController,
              label: "Full Name",
              hint: "Enter your full name",
              icon: Icons.person_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your name";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _phoneController,
              label: _isCreatingSociety
                  ? "Phone Number (Required for OTP)"
                  : "Phone Number (Optional)",
              hint: "e.g. 9876543210",
              icon: Icons.phone_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.phone,
              validator: (value) {
                final v = (value ?? '').trim();
                if (_isCreatingSociety) {
                  final digits = v.replaceAll(RegExp(r'[^\d]'), '');
                  if (digits.length != 10) {
                    return "Enter a valid 10-digit phone number";
                  }
                } else {
                  if (v.isNotEmpty) {
                    final digits = v.replaceAll(RegExp(r'[^\d]'), '');
                    if (digits.length != 10) {
                      return "Enter a valid 10-digit phone number";
                    }
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCreatingSociety
                      ? "Role (for new society creator)"
                      : "Role",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.admin_panel_settings_rounded,
                            color: theme.colorScheme.primary, size: 20),
                      ),
                      hintText: "Select role",
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18),
                    ),
                    items: (_isCreatingSociety
                            ? ["SUPER_ADMIN"]
                            : _roles.where((r) => r != "SUPER_ADMIN"))
                        .map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(
                          role == "SUPER_ADMIN" ? "SUPER ADMIN" : role,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedRole = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!_isCreatingSociety) ...[
              _PremiumField(
                controller: _pinController,
                label: "PIN/Password",
                hint: "Create a secure PIN (min 4 digits)",
                icon: Icons.lock_rounded,
                obscureText: _obscurePin,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.number,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePin
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
                validator: (value) {
                  if (!_isCreatingSociety) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter a PIN";
                    }
                    if (value.trim().length < 4) {
                      return "PIN must be at least 4 characters";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _PremiumField(
                controller: _confirmPinController,
                label: "Confirm PIN",
                hint: "Re-enter your PIN",
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirmPin,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _handleRegister(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPin
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirmPin = !_obscureConfirmPin),
                ),
                validator: (value) {
                  if (!_isCreatingSociety) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please confirm your PIN";
                    }
                    if (value.trim() != _pinController.text.trim()) {
                      return "PINs do not match";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _isCreatingSociety ? "VERIFY OTP & CREATE" : "CREATE ACCOUNT",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Already have an account? ",
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const AdminLoginScreen()),
                    );
                  },
                  child: Text(
                    "Login",
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateDropdown(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "State",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedState,
            isExpanded: true,
            menuMaxHeight: 320,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: theme.colorScheme.surface,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.primary),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              prefixIcon:
                  Icon(Icons.map_rounded, color: theme.colorScheme.primary),
            ),
            hint: Text(
              "Select state",
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            items: _stateOptions
                .map((st) => DropdownMenuItem<String>(
                      value: st['name'],
                      child: Text(
                        st['name'] ?? '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ))
                .toList(),
            selectedItemBuilder: (context) {
              return _stateOptions.map((st) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    st['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList();
            },
            validator: (value) {
              if (_isCreatingSociety && (value == null || value.isEmpty)) {
                return "Please select State";
              }
              return null;
            },
            onChanged: (value) {
              final stateMap = _stateOptions.firstWhere(
                (st) => st['name'] == value,
                orElse: () => {'id': '', 'name': ''},
              );

              setState(() {
                _selectedState = value;
                _selectedStateId = stateMap['id'];
                _selectedCity = null;
              });

              if (_selectedStateId != null && _selectedStateId!.isNotEmpty) {
                _loadCitiesForState(_selectedStateId!);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCityDropdown(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "City",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedCity,
            isExpanded: true,
            menuMaxHeight: 320,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: theme.colorScheme.surface,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.primary),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              prefixIcon: Icon(Icons.location_on_rounded,
                  color: theme.colorScheme.primary),
            ),
            hint: Text(
              "Select city",
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            items: _cityOptions
                .map((city) => DropdownMenuItem<String>(
                      value: city['name'],
                      child: Text(
                        city['name'] ?? '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ))
                .toList(),
            selectedItemBuilder: (context) {
              return _cityOptions.map((city) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    city['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList();
            },
            validator: (value) {
              if (_isCreatingSociety && (value == null || value.isEmpty)) {
                return "Please select City";
              }
              return null;
            },
            onChanged: (_selectedStateId == null || _selectedStateId!.isEmpty)
                ? null
                : (value) => setState(() => _selectedCity = value),
            disabledHint: Text(
              "Select state first",
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    required this.textInputAction,
    this.keyboardType,
    this.onSubmitted,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
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
            obscureText: obscureText,
            textInputAction: textInputAction,
            keyboardType: keyboardType,
            onFieldSubmitted: onSubmitted,
            validator: validator,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 20),
              ),
              suffixIcon: suffixIcon,
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
        ),
      ],
    );
  }
}

/// Returned after OTP verify
class _OtpAuthResult {
  final String uid;
  final String authPhone; // E.164
  const _OtpAuthResult({required this.uid, required this.authPhone});
}

/// Full-screen OTP verify UI (premium admin-like)
class OtpVerifyScreen extends StatefulWidget {
  final String phoneE164; // +91xxxxxxxxxx
  const OtpVerifyScreen({super.key, required this.phoneE164});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final _otpController = TextEditingController();

  bool _isLoading = false;

  String? _verificationId;
  int? _resendToken;

  int _resendSeconds = 0;
  Timer? _timer;

  bool get _canResend => _resendSeconds <= 0 && !_isLoading;

  @override
  void initState() {
    super.initState();
    _sendOtp(first: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer([int seconds = 30]) {
    _timer?.cancel();
    setState(() => _resendSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  String _maskE164(String e164) {
    if (e164.length < 6) return e164;
    final last4 = e164.substring(e164.length - 4);
    return '${e164.substring(0, 3)}******$last4';
  }

  Future<void> _sendOtp({required bool first}) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final res = await _authService.verifyPhoneNumber(
        phoneNumber: widget.phoneE164,
        resendToken: first ? null : _resendToken,
      );

      if (!mounted) return;
      setState(() {
        _verificationId = res.verificationId;
        _resendToken = res.resendToken;
      });
      _startResendTimer(30);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("OTP sent to ${_maskE164(widget.phoneE164)}"),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyPhoneError(e.code)),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim().replaceAll(RegExp(r'[^\d]'), '');
    if (code.length != 6) {
      _snack("Enter the 6-digit OTP");
      return;
    }

    final vid = _verificationId;
    if (vid == null || vid.isEmpty) {
      _snack("Session expired. Please resend OTP.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.signInWithPhoneCredential(
        verificationId: vid,
        smsCode: code,
      );

      final user = FirebaseAuth.instance.currentUser;
      final phone = user?.phoneNumber;

      if (user == null || phone == null || phone.isEmpty) {
        throw Exception("Auth user/phone missing after OTP verify.");
      }

      if (!mounted) return;
      Navigator.of(context)
          .pop(_OtpAuthResult(uid: user.uid, authPhone: phone));
    } on FirebaseAuthException catch (e) {
      _snack(_friendlyOtpError(e.code));
    } catch (_) {
      _snack("Verification failed. Try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static String _friendlyPhoneError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid phone number.';
      case 'too-many-requests':
        return 'Too many attempts. Try later.';
      case 'quota-exceeded':
        return 'OTP quota exceeded. Try later.';
      default:
        return 'Could not send OTP. Try again.';
    }
  }

  static String _friendlyOtpError(String code) {
    switch (code) {
      case 'invalid-verification-code':
        return 'Invalid OTP. Please try again.';
      case 'session-expired':
        return 'OTP expired. Please resend.';
      case 'invalid-verification-id':
        return 'Session expired. Please resend OTP.';
      default:
        return 'Verification failed. Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
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
                          child: Icon(Icons.arrow_back_rounded,
                              color: cs.onSurface, size: 20),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 190,
                    height: 140,
                    child: Image.asset(
                      'assets/illustrations/illustration_login_admin.png',
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, __, ___) => Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.verified_rounded,
                          size: 64,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "Verify OTP",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "OTP sent to ${_maskE164(widget.phoneE164)}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                          color: theme.dividerColor.withOpacity(0.8)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Enter 6-digit OTP",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withOpacity(0.72),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                            hintText: "••••••",
                            filled: true,
                            fillColor: theme.scaffoldBackgroundColor,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  BorderSide(color: cs.primary, width: 1.4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
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
                                    "VERIFY & CONTINUE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed:
                              _canResend ? () => _sendOtp(first: false) : null,
                          child: Text(
                            _canResend
                                ? "Resend OTP"
                                : "Resend in $_resendSeconds s",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _canResend
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(0.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
