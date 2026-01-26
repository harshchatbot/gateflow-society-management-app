import 'package:flutter/material.dart';
import '../core/storage.dart';
import '../core/app_logger.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import 'admin_shell_screen.dart';
import 'role_select_screen.dart';
import 'admin_onboarding_screen.dart';
import 'admin_signup_screen.dart';
import 'admin_pending_approval_screen.dart';
import '../services/admin_signup_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestore = FirestoreService();
  final AdminSignupService _signupService = AdminSignupService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
  if (!_formKey.currentState!.validate()) {
    return;
  }

  final email = _emailController.text.trim();
  final password = _passwordController.text.trim();

  setState(() => _isLoading = true);
  AppLogger.i("Admin login attempt", data: {"email": email});

  try {
    // Step 1: Sign in with Firebase Auth
    final userCredential = await _authService.signInAdmin(
      email: email,
      password: password,
    );

    final uid = userCredential.user?.uid;
    final userEmail = userCredential.user?.email ?? email;
    if (uid == null) {
      throw Exception("Failed to sign in");
    }

    // Step 2: Get membership from Firestore (pointer -> society member)
    final membership = await _firestore.getCurrentUserMembership();
    
    // Step 2a: If no membership, check for pending admin signup
    if (membership == null) {
      // User has no membership - redirect to pending approval screen
      if (userEmail != null) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminPendingApprovalScreen(email: userEmail),
          ),
        );
        return;
      }
      
      throw Exception("User membership not found and no email available");
    }

    final societyId = (membership['societyId'] as String?) ?? '';
    final String systemRole = (membership['systemRole'] as String?)?.toLowerCase() ?? 'admin';
    final societyRole = membership['societyRole'] as String?;
    final name = membership['name'] as String? ?? 'Admin';
    final bool isActive = membership['active'] == true;

    if (societyId.isEmpty) {
      throw Exception("Society not resolved");
    }

    // ✅ allow admin OR super_admin
    if (systemRole != 'admin' && systemRole != 'super_admin') {
      throw Exception("User is not an admin");
    }
    
    // Step 2b: Check if admin is pending approval (active == false)
    if (!isActive && systemRole == 'admin') {
      // User has pending approval, redirect to pending approval screen
      setState(() => _isLoading = false);
      if (!mounted) return;
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminPendingApprovalScreen(email: userEmail ?? email),
        ),
      );
      return;
    }

    // Step 3: Save Firebase session
    await Storage.saveFirebaseSession(
      uid: uid,
      societyId: societyId,
      systemRole: systemRole, // ✅ now defined
      societyRole: societyRole,
      name: name,
    );

    AppLogger.i("Admin login successful", data: {
      'uid': uid,
      'societyId': societyId,
      'systemRole': systemRole,
      'name': name,
    });

    setState(() => _isLoading = false);
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShellScreen(
          adminId: uid,
          adminName: name,
          societyId: societyId,
          role: (societyRole ?? 'ADMIN').toUpperCase(),
          systemRole: systemRole, // Pass systemRole to shell
        ),
      ),
    );
  } catch (e, stackTrace) {
    AppLogger.e("Admin login exception", error: e, stackTrace: stackTrace);
    if (mounted) {
      setState(() => _isLoading = false);

      String errorMsg = "Login failed. Please check your credentials.";
      if (e.toString().contains('user-not-found') || e.toString().contains('wrong-password')) {
        errorMsg = "Invalid email or password.";
      } else if (e.toString().contains('network')) {
        errorMsg = "Network error. Please check your connection.";
      } else if (e.toString().toLowerCase().contains('membership')) {
        errorMsg = "Your account is not linked to any society. Contact support.";
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
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          // Gradient Background (Purple theme)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.admin.withOpacity(0.15), // Purple gradient for admin
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
          GlassLoader(show: _isLoading, message: "Verifying Admin…"),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.admin, Color(0xFF7C3AED)], // Purple gradient
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.admin.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.admin_panel_settings_rounded,
            size: 50,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Admin Login",
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Society Management Portal",
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
            Text(
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
              label: "Email address",
              hint: "e.g. admin@example.com",
              icon: Icons.email_rounded,
              textInputAction: TextInputAction.next,
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
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                          _showError("Enter a valid email above, then tap Forgot Password.");
                          return;
                        }
                        try {
                          await _authService.sendPasswordResetEmail(email: email);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                "Password reset link sent to your email.",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          _showError("Could not send reset email. Please check the email or try again.");
                        }
                      },
                child: const Text(
                  "Forgot password?",
                  style: TextStyle(
                    color: AppColors.admin,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.admin, // Purple button
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
            const SizedBox(height: 16),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "New admin? ",
                      style: TextStyle(
                        color: AppColors.text2,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminSignupScreen()),
                        );
                      },
                      child: const Text(
                        "Sign Up",
                        style: TextStyle(
                          color: AppColors.admin,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminOnboardingScreen()),
                    );
                  },
                  child: Text(
                    "Create New Society (Super Admin)",
                    style: TextStyle(
                      color: AppColors.admin.withOpacity(0.8),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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
}

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
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
    this.onSubmitted,
    this.suffixIcon,
    this.validator,
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
                  color: AppColors.admin.withOpacity(0.15), // Purple for admin
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.admin, size: 20),
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
