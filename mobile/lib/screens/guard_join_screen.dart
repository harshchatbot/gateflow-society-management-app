import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_logger.dart';
import '../core/storage.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_loader.dart';
import 'guard_shell_screen.dart';

class GuardJoinScreen extends StatefulWidget {
  const GuardJoinScreen({super.key});

  @override
  State<GuardJoinScreen> createState() => _GuardJoinScreenState();
}

class _GuardJoinScreenState extends State<GuardJoinScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();
  final _shiftController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isVerifying = false;
  bool _isProcessing = false;
  String? _societyId;
  String? _error;
  XFile? _selfie;

  // ✅ Prefill + lock username when user already authenticated via Phone OTP.
  String? _prefilledUsername;
  bool _usernameLocked = false;

  @override
  void initState() {
    super.initState();
    // If already logged in (OTP), prefill immediately.
    _maybePrefillUsernameFromAuth();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _pinController.dispose();
    _shiftController.dispose();
    super.dispose();
  }

  void _maybePrefillUsernameFromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber;
    if (phone != null && phone.isNotEmpty) {
      final normalized = FirebaseAuthService.normalizePhoneForIndia(phone);
      _usernameController.text = normalized;
      _prefilledUsername = normalized;
      _usernameLocked = true;
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = "Please enter a valid 6-digit code.");
      return;
    }
    setState(() {
      _error = null;
      _isVerifying = true;
    });
    try {
      final societyId = await _firestore.getGuardJoinCode(code);
      if (!mounted) return;
      if (societyId != null && societyId.isNotEmpty) {
        setState(() {
          _societyId = societyId;
          _isVerifying = false;
        });
        // Prefill username after code verification too (covers any late auth state).
        _maybePrefillUsernameFromAuth();
      } else {
        setState(() {
          _error = "Invalid or expired code. Please ask admin for a new code.";
          _isVerifying = false;
        });
      }
    } catch (e, st) {
      AppLogger.e("GuardJoinScreen verify code error", error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = "Could not verify code. Please try again.";
        _isVerifying = false;
      });
    }
  }

  Future<void> _handleJoin() async {
    if (!_formKey.currentState!.validate()) return;
    final societyId = _societyId;
    if (societyId == null) {
      setState(() {
        _error = "Please enter the 6-digit code from your admin first.";
      });
      return;
    }

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final pin = _pinController.text.trim();

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      AppLogger.i("GuardJoinScreen creating guard membership", data: {
        'societyId': societyId,
        'username': username,
      });

      // If user is already authenticated (e.g. via Phone OTP), reuse current UID
      // and skip creating a new Firebase Auth user.
      final currentUser = FirebaseAuth.instance.currentUser;
      String? email;
      String? phone;
      String uid;

      if (currentUser != null) {
        uid = currentUser.uid;
        email = currentUser.email;
        phone = currentUser.phoneNumber;
      } else {
        final cred = await _authService.createGuardAccountWithUsername(
          username: username,
          pin: pin,
        );
        uid = cred.user?.uid ?? '';
        if (uid.isEmpty) {
          throw Exception("Guard account creation failed (uid null)");
        }

        // Derive email/phone from username (legacy email/PIN flow)
        if (username.contains('@')) {
          email = username.toLowerCase();
        } else {
          phone = username;
        }
      }

      // Upload selfie if provided
      String? photoUrl;
      if (_selfie != null) {
        try {
          final storage = FirebaseStorage.instance;
          final ref = storage.ref().child('societies/$societyId/guards/$uid.jpg');
          final file = File(_selfie!.path);
          final task = await ref.putFile(file);
          photoUrl = await task.ref.getDownloadURL();
        } catch (e, st) {
          AppLogger.e("GuardJoinScreen selfie upload failed", error: e, stackTrace: st);
        }
      }

      await _firestore.setMember(
        societyId: societyId,
        uid: uid,
        systemRole: 'guard',
        societyRole: null,
        name: name,
        phone: phone,
        email: email,
        flatNo: null,
        photoUrl: photoUrl,
        shiftTimings:
            _shiftController.text.trim().isEmpty ? null : _shiftController.text.trim(),
        active: true,
      );

      // Ensure phone is registered in root pointer + unique_phones for mobile-first auth.
      if (phone != null && phone.isNotEmpty) {
        final normalized = FirebaseAuthService.normalizePhoneForIndia(phone);
        try {
          await _firestore.setMemberPhone(
            societyId: societyId,
            uid: uid,
            normalizedE164: normalized,
          );
        } catch (_) {
          // non-fatal
        }
      }

      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: societyId,
        systemRole: 'guard',
        name: name,
      );

      await Storage.saveGuardSession(
        guardId: uid,
        guardName: name,
        societyId: societyId,
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => GuardShellScreen(
            guardId: uid,
            guardName: name,
            societyId: societyId,
          ),
        ),
        (route) => false,
      );
    } catch (e, st) {
      AppLogger.e("GuardJoinScreen join error", error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = "Failed to join as guard. Please try again or ask admin for a new code.";
      });
    }
  }

  Widget _buildIllustrationHeader() {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SizedBox(
          width: 160,
          height: 120,
          child: Image.asset(
            'assets/mascot/senti_guard_onboarding.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.shield_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, {required String label, String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: theme.colorScheme.surface.withOpacity(0.92),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.8), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCode = _societyId != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        title: Text(
          "Join as Guard",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
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
                    theme.colorScheme.primary.withOpacity(0.10),
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildIllustrationHeader(),
                  const SizedBox(height: 14),
                  Text(
                    hasCode
                        ? "Code verified. Complete your guard setup."
                        : "Enter the 6-digit code from your admin to join as a guard.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildErrorBanner(theme),
                  if (_error != null) const SizedBox(height: 12),
                  if (!hasCode) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.55)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Guard Join Code",
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 10,
                              fontFamily: 'monospace',
                            ),
                            decoration: _inputDecoration(theme, label: "6-digit code", hint: "000000").copyWith(
                              counterText: "",
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isVerifying ? null : _verifyCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isVerifying) ...[
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text("Verifying…", style: TextStyle(fontWeight: FontWeight.w900)),
                                  ] else ...[
                                    const Icon(Icons.arrow_forward_rounded),
                                    const SizedBox(width: 10),
                                    const Text("Continue", style: TextStyle(fontWeight: FontWeight.w900)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (hasCode) ...[
                    const SizedBox(height: 10),
                    Form(
                      key: _formKey,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.55)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 80,
                                    );
                                    if (picked != null) {
                                      setState(() => _selfie = picked);
                                    }
                                  },
                                  child: CircleAvatar(
                                    radius: 30,
                                    backgroundColor: theme.colorScheme.surface,
                                    backgroundImage: _selfie != null ? FileImage(File(_selfie!.path)) : null,
                                    child: _selfie == null
                                        ? Icon(Icons.camera_alt_rounded, color: theme.colorScheme.onSurface.withOpacity(0.75))
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Selfie (optional)",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Tap to capture for verification",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 80,
                                    );
                                    if (picked != null) {
                                      setState(() => _selfie = picked);
                                    }
                                  },
                                  child: Text(
                                    _selfie == null ? "Add" : "Retake",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(theme, label: "Full Name"),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return "Please enter name";
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _usernameController,
                              textInputAction: TextInputAction.next,
                              readOnly: _usernameLocked,
                              decoration: _inputDecoration(
                                theme,
                                label: "Phone number or email (username)",
                                hint: _usernameLocked ? null : "+91XXXXXXXXXX or email",
                                suffixIcon: _usernameLocked
                                    ? Icon(Icons.lock_rounded, color: theme.colorScheme.onSurface.withOpacity(0.55))
                                    : null,
                              ).copyWith(
                                helperText: _usernameLocked ? "Using your OTP phone number" : null,
                              ),
                              validator: (value) {
                                final v = value?.trim() ?? "";
                                if (v.isEmpty) return "Please enter phone or email";
                                if (_usernameLocked && _prefilledUsername != null && v != _prefilledUsername) {
                                  return "Phone number must match OTP login";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 6,
                              decoration: _inputDecoration(theme, label: "Set Guard Password (6 digits)").copyWith(
                                counterText: "",
                              ),
                              validator: (value) {
                                final v = value?.trim() ?? "";
                                if (v.length != 6 || int.tryParse(v) == null) {
                                  return "Please enter exactly 6 digits (required by sign-in)";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _shiftController,
                              textInputAction: TextInputAction.done,
                              decoration: _inputDecoration(theme, label: "Shift timings (optional)", hint: "8am–4pm"),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing ? null : _handleJoin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text(
                                  "Confirm & Join",
                                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          AppLoader.overlay(showAfter: const Duration(milliseconds: 300), show: _isProcessing, message: "Creating guard account…"),
        ],
      ),
    );
  }
}
