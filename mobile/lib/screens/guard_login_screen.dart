import 'dart:ui'; // kept (existing blur overlay uses ImageFilter)
import 'package:flutter/material.dart';
import '../widgets/powered_by_footer.dart';
import '../core/storage.dart';
import 'new_visitor_screen.dart';

// Premium palette + reusable glass loader (doesn't change functionality)
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';

class GuardLoginScreen extends StatefulWidget {
  const GuardLoginScreen({super.key});

  @override
  State<GuardLoginScreen> createState() => _GuardLoginScreenState();
}

class _GuardLoginScreenState extends State<GuardLoginScreen> {
  final _guardIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _guardIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_guardIdController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Guard ID and Password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2));

    // --- MOCK DATA ---
    final String guardId = _guardIdController.text;
    const String guardName = "Verified Guard";
    const String societyId = "SOC-001";
    // -----------------

    await Storage.saveGuardSession(
      guardId: guardId,
      guardName: guardName,
      societyId: societyId,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => NewVisitorScreen(
            guardId: guardId,
            guardName: guardName,
            societyId: societyId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // NOTE: UI updated only. Existing login flow, validations, storage, navigation untouched.

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background subtle gradient (premium, light)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primarySoft.withOpacity(0.75),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),

          // Main UI
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Brand mark
                          Container(
                            height: 72,
                            width: 72,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              size: 34,
                              color: AppColors.primary,
                            ),
                          ),

                          const SizedBox(height: 18),
                          const Text(
                            "GateFlow",
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppColors.text,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Guard Access Portal",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.text2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Login card
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 26,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  "Sign in",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Use your Guard ID and password provided by the society admin.",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text2,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                _PremiumField(
                                  controller: _guardIdController,
                                  label: "Guard ID",
                                  hint: "e.g. G-102",
                                  icon: Icons.badge_outlined,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 14),

                                _PremiumField(
                                  controller: _passwordController,
                                  label: "Password",
                                  hint: "••••••••",
                                  icon: Icons.lock_outline,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleLogin(),
                                ),
                                const SizedBox(height: 18),

                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text(
                                      "Secure Login",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // Tiny helper row (non-functional, just UI)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.verified_user_outlined,
                                        size: 16, color: AppColors.textMuted),
                                    SizedBox(width: 6),
                                    Text(
                                      "Your access is logged for security.",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Footer (unchanged)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: PoweredByFooter(),
                ),
              ],
            ),
          ),

          // ✅ Full screen glassmorphism spinner for loading
          // (doesn't change functionality; just replaces the old overlay UI)
          GlassLoader(
            show: _isLoading,
            message: "Verifying Credentials…",
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

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    required this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.text2),
          labelText: label,
          hintText: hint,
          floatingLabelStyle: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
          ),
          hintStyle: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}
