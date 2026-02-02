import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import 'admin_login_screen.dart';
import 'guard_login_screen.dart';
import 'phone_otp_login_screen.dart';
import 'resident_login_screen.dart';

/// Auth entry: primary = "Continue with Mobile Number", secondary = "Login with Email".
/// Role determines which email login screen to open and optional subtitle.
enum AuthLoginRole { guard, resident, admin }

class AuthLoginEntryScreen extends StatelessWidget {
  final AuthLoginRole role;

  const AuthLoginEntryScreen({super.key, required this.role});

  String get _roleTitle {
    switch (role) {
      case AuthLoginRole.guard:
        return 'Guard';
      case AuthLoginRole.resident:
        return 'Resident';
      case AuthLoginRole.admin:
        return 'Admin';
    }
  }

  Widget _emailScreen() {
    switch (role) {
      case AuthLoginRole.guard:
        return const GuardLoginScreen();
      case AuthLoginRole.resident:
        return const ResidentLoginScreen();
      case AuthLoginRole.admin:
        return const AdminLoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Login as $_roleTitle',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Primary: Continue with Mobile Number
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PhoneOtpLoginScreen(
                          roleHint: _roleTitle.toLowerCase(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.phone_android_rounded, size: 22),
                  label: const Text('Continue with Mobile Number'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Secondary: Login with Email (small)
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => _emailScreen()),
                    );
                  },
                  child: Text(
                    'Login with Email',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
