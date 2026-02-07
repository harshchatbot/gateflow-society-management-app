import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_logger.dart';
import '../services/resident_signup_service.dart';
import '../services/firestore_service.dart';
import '../ui/app_colors.dart';
import '../ui/app_loader.dart';
import '../ui/app_icons.dart';
import 'resident_login_screen.dart';
import 'package:flutter/foundation.dart';


class ResidentSignupScreen extends StatefulWidget {
  const ResidentSignupScreen({super.key});

  @override
  State<ResidentSignupScreen> createState() => _ResidentSignupScreenState();
}

class _ResidentSignupScreenState extends State<ResidentSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _flatNoController = TextEditingController();
  final _societyCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final ResidentSignupService _signupService = ResidentSignupService();
  final FirestoreService _firestoreService = FirestoreService();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _signupSuccess = false;
  String? _societyId;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _flatNoController.dispose();
    _societyCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate society code first
    if (_societyId == null) {
      final societyCode = _societyCodeController.text.trim().toUpperCase();
      if (societyCode.isEmpty) {
        _showError("Please enter a society code");
        return;
      }

      setState(() => _isLoading = true);
      final resolvedSocietyId = await _firestoreService.getSocietyByCode(societyCode);
      debugPrint("Resolved society id: $resolvedSocietyId");
      if (!mounted) return;
      
      if (resolvedSocietyId == null) {
        setState(() => _isLoading = false);
        _showError("Invalid society code. Please check and try again.");
        return;
      }
      
      setState(() {
        _societyId = resolvedSocietyId;
        _isLoading = false;
      });
    }

    setState(() => _isLoading = true);

    try {
      final result = await _signupService.createSignupRequest(
        societyCode: _societyCodeController.text.trim(),
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        flatNo: _flatNoController.text.trim(),
        password: _passwordController.text,
      );


      if (!mounted) return;

      if (result.isSuccess) {
        setState(() {
          _isLoading = false;
          _signupSuccess = true;
        });
        AppLogger.i("Signup request created successfully");
      } else {
        setState(() => _isLoading = false);
        _showError(result.error?.userMessage ?? "Failed to create signup request");
      }
    } catch (e, stackTrace) {
      AppLogger.e("Signup exception", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("An error occurred. Please try again.");
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
                MaterialPageRoute(builder: (_) => const ResidentLoginScreen()),
              );
            }
          },
        ),
      ),
      body: Stack(
        children: [
          // Gradient Background (onboarding theme)
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
                  if (_signupSuccess)
                    _buildSuccessCard()
                  else
                    _buildSignupForm(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          AppLoader.overlay(show: _isLoading, message: "Creating Account…"),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 140,
          child: Image.asset(
            'assets/illustrations/illustration_signup_resident.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.person_add_rounded,
                size: 64,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Resident Signup",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Create your account",
          style: TextStyle(
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildSignupForm() {
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
              "Enter your details",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _PremiumField(
              controller: _nameController,
              label: "Full Name",
              hint: "e.g. John Doe",
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
              controller: _phoneController,
              label: "Phone Number",
              hint: "10-digit mobile number",
              icon: Icons.phone_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your phone number";
                }
                if (value.length != 10) {
                  return "Phone number must be 10 digits";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _flatNoController,
              label: "Flat / Unit Number",
              hint: "e.g. A-101",
              icon: Icons.home_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter your flat number";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _societyCodeController,
              label: "Society Code",
              hint: "Enter your society code",
              icon: Icons.business_rounded,
              textInputAction: TextInputAction.next,
              enabled: _societyId == null,
              validator: (value) {
                if (_societyId == null && (value == null || value.trim().isEmpty)) {
                  return "Please enter your society code";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _passwordController,
              label: "Password",
              hint: "Create a password",
              icon: Icons.lock_rounded,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
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
                  return "Please enter a password";
                }
                if (value.length < 6) {
                  return "Password must be at least 6 characters";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _confirmPasswordController,
              label: "Confirm Password",
              hint: "Re-enter your password",
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSignup(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.text2,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please confirm your password";
                }
                if (value != _passwordController.text) {
                  return "Passwords do not match";
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "SIGN UP",
                  style: TextStyle(
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
                const Text(
                  "Already have an account? ",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const ResidentLoginScreen()),
                    );
                  },
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
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

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primary,
              size: 50,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Signup Request Submitted!",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            "Your signup request has been sent to the admin for approval. You will be able to login once your request is approved.",
            style: TextStyle(
              fontSize: 15,
              color: AppColors.text2,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ResidentLoginScreen()),
                );
              },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "GO TO LOGIN",
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
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool enabled;

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
    this.inputFormatters,
    this.maxLength,
    this.enabled = true,
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
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            enabled: enabled,
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
