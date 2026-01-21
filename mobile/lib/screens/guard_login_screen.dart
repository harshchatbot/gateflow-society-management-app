import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // Ensure url_launcher is in pubspec.yaml
import '../core/storage.dart';
import '../services/visitor_service.dart';

// UI system
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../ui/app_icons.dart';

import 'guard_shell_screen.dart';
import '../core/app_logger.dart';

class GuardLoginScreen extends StatefulWidget {
  const GuardLoginScreen({super.key});

  @override
  State<GuardLoginScreen> createState() => _GuardLoginScreenState();
}

class _GuardLoginScreenState extends State<GuardLoginScreen> {
  final _guardIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _visitorService = VisitorService();
  bool _isLoading = false;

  @override
  void dispose() {
    _guardIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final guardIdInput = _guardIdController.text.trim();
    final password = _passwordController.text.trim();
    debugPrint("guardIdInput_______ : ${guardIdInput}");
    debugPrint("password : ${password}");
    // 1. Basic Validation
    if (guardIdInput.isEmpty || password.isEmpty) {
      _showError("Please enter Guard ID and Password");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Call the dedicated Profile API (The one we added to Swagger)
      // This returns Result<Map<String, dynamic>>
      final result = await _visitorService.getGuardProfile(guardIdInput);
      
      debugPrint("Login API Response: ${result.data}");

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final data = result.data!;

        // 3. Extract Dynamic Data from Backend
        // We use .toString() to be safe against integer IDs in Google Sheets
        final String realName = data['name']?.toString() ?? 
                             data['guard_name']?.toString() ?? 
                             data['full_name']?.toString() ?? 
                             "Unknown Guard";

        final String realSociety = data['society_id']?.toString() ?? 
                                  data['society_name']?.toString() ?? 
                                  "Unknown Society";

        debugPrint("Extracted Name: $realName"); // Check this in console!

        await Storage.saveGuardSession(
          guardId: guardIdInput,
          guardName: realName,
          societyId: realSociety,
        );

        setState(() => _isLoading = false);

        // 5. Navigation: Move to the Dashboard with real data
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GuardShellScreen(
              guardId: guardIdInput,
              guardName: realName,
              societyId: realSociety,
            ),
          ),
        );
      } else {
        // 6. Error Handling
        setState(() => _isLoading = false);
        _showError(result.error?.userMessage ?? "Invalid Guard ID or unauthorized access");
      }
    } catch (e) {
      debugPrint("Login Crash: $e");
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primarySoft.withOpacity(0.75), AppColors.bg],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        children: [
                          _buildBrandLogo(),
                          const SizedBox(height: 32),
                          _buildLoginForm(),
                        ],
                      ),
                    ),
                  ),
                ),
                // Optimized Footer with your requested links and text
                const _PremiumFooter(),
              ],
            ),
          ),
          GlassLoader(show: _isLoading, message: "Verifying Credentials…"),
        ],
      ),
    );
  }

  Widget _buildBrandLogo() {
    return Column(
      children: [
        Container(
          height: 80, width: 80,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: const Icon(AppIcons.guard, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 18),
        const Text("GateFlow", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.text, letterSpacing: -0.5)),
        Text("Secure Society Access", style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 30, offset: const Offset(0, 15))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Guard Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text)),
          const SizedBox(height: 20),
          _PremiumField(controller: _guardIdController, label: "Guard ID", hint: "Enter ID", icon: Icons.badge_outlined, textInputAction: TextInputAction.next),
          const SizedBox(height: 16),
          _PremiumField(controller: _passwordController, label: "Password", hint: "••••••••", icon: Icons.lock_outline, obscureText: true, textInputAction: TextInputAction.done, onSubmitted: (_) => _handleLogin()),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text("SECURE LOGIN", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------ Updated Clickable Footer ------------------ */

class _PremiumFooter extends StatelessWidget {
  const _PremiumFooter();

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Powered by ",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2.withOpacity(0.8),
                ),
              ),
              GestureDetector(
                onTap: () => _launchUrl("https://techfilabs.com"),
                child: const Text(
                  "TechFi Labs",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "A unit of ",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
              GestureDetector(
                onTap: () => _launchUrl("https://thetechnologyfiction.com"),
                child: Text(
                  "The Technology Fiction",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text2.withOpacity(0.9),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
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

  const _PremiumField({required this.controller, required this.label, required this.hint, required this.icon, this.obscureText = false, required this.textInputAction, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text2)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}