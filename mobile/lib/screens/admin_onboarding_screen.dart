import 'package:flutter/material.dart';
import '../core/app_logger.dart';
import '../core/env.dart';
import '../services/admin_service.dart';
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import 'admin_shell_screen.dart';
import 'admin_login_screen.dart';
import '../core/storage.dart';

/// Admin Onboarding Screen
/// 
/// Allows new admins to register/create their account.
/// Theme: Purple/Admin theme
class AdminOnboardingScreen extends StatefulWidget {
  const AdminOnboardingScreen({super.key});

  @override
  State<AdminOnboardingScreen> createState() => _AdminOnboardingScreenState();
}

class _AdminOnboardingScreenState extends State<AdminOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _societyIdController = TextEditingController();
  final _adminIdController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  
  late final AdminService _adminService = AdminService(
    baseUrl: Env.apiBaseUrl.isNotEmpty ? Env.apiBaseUrl : "http://192.168.29.195:8000",
  );
  
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  String _selectedRole = "ADMIN";

  final List<String> _roles = [
    "ADMIN",
    "PRESIDENT",
    "SECRETARY",
    "TREASURER",
    "COMMITTEE",
  ];

  @override
  void dispose() {
    _societyIdController.dispose();
    _adminIdController.dispose();
    _adminNameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final societyId = _societyIdController.text.trim();
    final adminId = _adminIdController.text.trim();
    final adminName = _adminNameController.text.trim();
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();

    setState(() => _isLoading = true);
    AppLogger.i("Admin registration attempt", data: {
      "society_id": societyId,
      "admin_id": adminId,
      "role": _selectedRole,
    });

    try {
      final result = await _adminService.register(
        societyId: societyId,
        adminId: adminId,
        adminName: adminName,
        pin: pin,
        phone: phone.isEmpty ? null : phone,
        role: _selectedRole,
      );

      if (!mounted) return;

      AppLogger.i("Admin registration response", data: {
        "success": result.isSuccess,
        "error": result.error,
      });

      if (result.isSuccess && result.data != null) {
        final data = result.data!;
        AppLogger.i("Admin registered successfully", data: data);

        // Extract admin info from response
        final adminData = data['admin'] as Map<String, dynamic>? ?? data;
        final String registeredAdminId = (adminData['admin_id'] ?? adminId).toString();
        final String registeredAdminName = (adminData['admin_name'] ?? adminName).toString();
        final String realSocietyId = (adminData['society_id'] ?? societyId).toString();
        final String role = (adminData['role'] ?? _selectedRole).toString();

        // Save session
        await Storage.saveAdminSession(
          adminId: registeredAdminId,
          adminName: registeredAdminName,
          societyId: realSocietyId,
          role: role,
        );

        AppLogger.i("Admin session saved successfully");

        setState(() => _isLoading = false);

        if (!mounted) return;

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Account created successfully!",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.admin,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate to admin shell
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminShellScreen(
              adminId: registeredAdminId,
              adminName: registeredAdminName,
              societyId: realSocietyId,
              role: role,
            ),
          ),
        );
      } else {
        AppLogger.e("Admin registration failed", error: result.error);
        setState(() => _isLoading = false);
        _showError(result.error ?? "Registration failed. Please try again.");
      }
    } catch (e, stackTrace) {
      AppLogger.e("Admin registration exception", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Connection error. Please try again.");
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
              MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
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
                    AppColors.admin.withOpacity(0.15),
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
                  _buildRegistrationForm(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          GlassLoader(show: _isLoading, message: "Creating Account…"),
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
              colors: [AppColors.admin, Color(0xFF7C3AED)],
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
            Icons.person_add_rounded,
            size: 50,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Admin Onboarding",
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Create your admin account",
          style: TextStyle(
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildRegistrationForm() {
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
              "Fill in your details",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _PremiumField(
              controller: _societyIdController,
              label: "Society ID",
              hint: "e.g. SOC-001",
              icon: Icons.apartment_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter Society ID";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PremiumField(
              controller: _adminIdController,
              label: "Admin ID",
              hint: "Choose a unique Admin ID",
              icon: Icons.badge_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter Admin ID";
                }
                if (value.trim().length < 3) {
                  return "Admin ID must be at least 3 characters";
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
              label: "Phone Number (Optional)",
              hint: "e.g. 9876543210",
              icon: Icons.phone_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  if (value.trim().length < 10) {
                    return "Please enter a valid phone number";
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            // Role Selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Role",
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
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.admin.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.admin, size: 20),
                      ),
                      hintText: "Select role",
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                    items: _roles.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(
                          role,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedRole = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                  _obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.text2,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePin = !_obscurePin);
                },
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter a PIN";
                }
                if (value.trim().length < 4) {
                  return "PIN must be at least 4 characters";
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
                  _obscureConfirmPin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.text2,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureConfirmPin = !_obscureConfirmPin);
                },
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please confirm your PIN";
                }
                if (value.trim() != _pinController.text.trim()) {
                  return "PINs do not match";
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.admin,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "CREATE ACCOUNT",
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
                Text(
                  "Already have an account? ",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                    );
                  },
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      color: AppColors.admin,
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
            keyboardType: keyboardType,
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
                  color: AppColors.admin.withOpacity(0.15),
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
