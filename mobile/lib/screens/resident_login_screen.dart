import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/app_logger.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/invite_claim_service.dart';
import '../core/session_gate_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// UI system
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';

import 'resident_shell_screen.dart';
import 'resident_pending_approval_screen.dart';
import 'onboarding_choose_role_screen.dart';
import 'resident_signup_screen.dart';

class ResidentLoginScreen extends StatefulWidget {
  const ResidentLoginScreen({super.key});

  @override
  State<ResidentLoginScreen> createState() => _ResidentLoginScreenState();
}

class _ResidentLoginScreenState extends State<ResidentLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    AppLogger.i("Resident login attempt");

    try {
      // 1) Firebase Auth sign-in
      final userCredential = await _authService.signInResidentWithEmail(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      final uid = user?.uid;

      // Don't log raw email in production logs

      if (uid == null) {
        throw Exception("Failed to sign in (uid null)");
      }

      // 2) Get membership (now returns even if active=false)
      Map<String, dynamic>? membership =
          await _firestore.getCurrentUserMembership();
      // 3) If membership missing -> attempt invite claim -> retry membership
      if (membership == null) {
        AppLogger.w(
          "Membership not found after login. Trying invite claim...",
          data: {"uid": uid, "email": email},
        );

        final claimRes = await InviteClaimService().claimInviteAuto();

        if (!claimRes.claimed) {
          throw Exception(
            "No membership found and no pending invite available for this email.",
          );
        }

        membership = await _firestore.getCurrentUserMembership();
        if (membership == null) {
          throw Exception("Membership still not found after invite claim.");
        }
      }

      // 4) Extract membership data
      final societyId = (membership['societyId'] as String?)?.trim() ?? '';
      final systemRole =
          (membership['systemRole'] as String?)?.trim() ?? 'resident';
      final name = (membership['name'] as String?)?.trim() ?? 'Resident';
      final flatNo = (membership['flatNo'] as String?)?.trim() ?? '';
      final bool isActive = membership['active'] == true;

      if (societyId.isEmpty) {
        throw Exception("Membership missing societyId.");
      }

      if (systemRole != 'resident') {
        throw Exception("User is not a resident (role=$systemRole).");
      }

      // 5) Check if resident is pending approval (active == false)
      if (!isActive && systemRole == 'resident') {
        setState(() => _isLoading = false);
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResidentPendingApprovalScreen(
              residentId: uid,
              societyId: societyId,
              residentName: name.isNotEmpty ? name : 'Resident',
              email: email, // optional, safe
            ),
          ),
        );
        return;
      }

      // 5a) Post-login gate: block if society inactive
      final gate = SessionGateService();
      final gateResult = await gate.validateSessionAfterLogin(uid);
      if (!gateResult.allowed) {
        await FirebaseAuth.instance.signOut();
        await Storage.clearAllSessions();
        await Storage.clearFirebaseSession();
        GateBlockMessage.set(gateResult.userMessage ??
            'This society is currently inactive. Please contact the society admin.');
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
        );
        return;
      }

      // 6) Save session
      await Storage.saveFirebaseSession(
        uid: uid,
        societyId: societyId,
        systemRole: systemRole,
        name: name,
      );

      AppLogger.i("Resident session saved successfully");

      setState(() => _isLoading = false);

      if (!mounted) return;

      // Non-blocking: suggest adding phone for easier login next time (email-only users).
      final memberPhone = (membership['phone'] ?? '').toString().trim();
      if (memberPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Add your phone in Profile for easier login next time.'),
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResidentShellScreen(
            residentId: uid,
            residentName: name,
            societyId: societyId,
            flatNo: flatNo,
          ),
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.e("Resident login exception", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMsg = "Login failed. Please try again.";
        if (e.toString().contains('user-not-found')) {
          errorMsg = "No account found with this email.";
        } else if (e.toString().contains('wrong-password')) {
          errorMsg = "Incorrect password. Please try again.";
        } else if (e.toString().contains('invalid-email')) {
          errorMsg = "Invalid email address.";
        } else if (e.toString().contains('No membership found')) {
          errorMsg = "No membership found. Please contact your society admin.";
        }
        _showError(errorMsg);
      }
    }
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.text,
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
          // Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.15),
                    AppColors.bg,
                    AppColors.bg,
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
                  _buildLoginForm(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          AppLoader.overlay(
              show: _isLoading, message: "Verifying Credentials…"),
        ],
      ),
    );
  }

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
        const Text(
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

  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
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
            const Text(
              "Enter your credentials",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _PremiumField(
              controller: _emailController,
              label: "Email Address",
              hint: "e.g. resident@example.com",
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
              controller: _passwordController,
              label: "Password",
              hint: "Enter your password",
              icon: Icons.lock_rounded,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleLogin(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.text2,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your password";
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        final email = _emailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          _showError(
                              "Please enter a valid email address first.");
                          return;
                        }
                        try {
                          await _authService.sendPasswordResetEmail(
                              email: email);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  "Password reset email sent! Check your inbox.",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            String errorMsg = "Failed to send reset email.";
                            if (e.toString().contains('user-not-found')) {
                              errorMsg = "No account found with this email.";
                            }
                            _showError(errorMsg);
                          }
                        }
                      },
                child: const Text(
                  "Forgot password?",
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ResidentSignupScreen()),
                    );
                  },
                  child: const Text(
                    "Sign Up",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ).copyWith(
                  elevation: WidgetStateProperty.resolveWith<double>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.pressed)) {
                        return 0;
                      }
                      return 0;
                    },
                  ),
                ),
                child: const Text(
                  "LOGIN",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------ Premium Input ------------------ */

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    required this.textInputAction,
    this.onSubmitted,
    this.keyboardType,
    this.validator,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.text2,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
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
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onFieldSubmitted: onSubmitted,
            validator: validator,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
            decoration: InputDecoration(
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              suffixIcon: suffixIcon,
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
        ),
      ],
    );
  }
}
