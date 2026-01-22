import 'dart:ui';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../services/resident_service.dart';

// UI system
import '../ui/app_colors.dart';
import '../ui/glass_loader.dart';
import '../ui/app_icons.dart';

import 'resident_shell_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class ResidentLoginScreen extends StatefulWidget {
  const ResidentLoginScreen({super.key});

  @override
  State<ResidentLoginScreen> createState() => _ResidentLoginScreenState();
}

class _ResidentLoginScreenState extends State<ResidentLoginScreen> {
  final _societyIdController = TextEditingController();
  final _flatNoController = TextEditingController();
  final _phoneController = TextEditingController();

  late final ResidentService _residentService = ResidentService(
  baseUrl: dotenv.env["API_BASE_URL"] ?? "http://192.168.29.195:8000",
    );

  bool _isLoading = false;

  @override
  void dispose() {
    _societyIdController.dispose();
    _flatNoController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final societyId = _societyIdController.text.trim();
    final flatNo = _flatNoController.text.trim().toUpperCase();
    final phone = _phoneController.text.trim();

    if (societyId.isEmpty || flatNo.isEmpty) {
      _showError("Please enter Society ID and Flat No");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // MVP: call backend profile/lookup (by societyId + flatNo)
      final result = await _residentService.getProfile(

        societyId: societyId,
        flatNo: flatNo,
        phone: phone.isEmpty ? null : phone,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final data = result.data!;

        // Be flexible with keys coming from backend/sheets
        final String residentId =
            (data['resident_id'] ?? data['id'] ?? data['residentId'])?.toString() ?? "";
        final String residentName =
            (data['resident_name'] ?? data['name'] ?? data['full_name'])?.toString() ?? "Resident";
        final String realSocietyId =
            (data['society_id'] ?? data['societyId'])?.toString() ?? societyId;
        final String realFlatNo =
            (data['flat_no'] ?? data['flatNo'])?.toString() ?? flatNo;

        if (residentId.isEmpty) {
          setState(() => _isLoading = false);
          _showError("Resident profile invalid (missing resident_id).");
          return;
        }

        await Storage.saveResidentSession(
          residentId: residentId,
          residentName: residentName,
          societyId: realSocietyId,
          flatNo: realFlatNo,
        );

        setState(() => _isLoading = false);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResidentShellScreen(
              residentId: residentId,
              residentName: residentName,
              societyId: realSocietyId,
              flatNo: realFlatNo,
            ),
          ),
        );
      } else {
        setState(() => _isLoading = false);
        _showError(result.error ?? "Resident not found / unauthorized");
      }
    } catch (e) {
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
                const _ResidentFooter(),
              ],
            ),
          ),
          GlassLoader(show: _isLoading, message: "Verifying Resident…"),
        ],
      ),
    );
  }

  Widget _buildBrandLogo() {
    return Column(
      children: [
        Container(
          height: 80,
          width: 80,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.home_rounded, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 18),
        const Text(
          "GateFlow",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppColors.text,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          "Resident Access",
          style: TextStyle(
            color: AppColors.text2,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Resident Login",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 20),

          _PremiumField(
            controller: _societyIdController,
            label: "Society ID",
            hint: "e.g. SOC-001",
            icon: Icons.apartment_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          _PremiumField(
            controller: _flatNoController,
            label: "Flat No",
            hint: "e.g. A-101",
            icon: Icons.home_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // optional for now (we can enforce later)
          _PremiumField(
            controller: _phoneController,
            label: "Phone (optional)",
            hint: "e.g. 98765xxxxx",
            icon: Icons.phone_outlined,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.phone,
            onSubmitted: (_) => _handleLogin(),
          ),

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
              child: const Text(
                "CONTINUE",
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------ Footer (simple) ------------------ */

class _ResidentFooter extends StatelessWidget {
  const _ResidentFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Text(
        "Secure approvals • Powered by TechFi Labs",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text2.withOpacity(0.8),
        ),
      ),
    );
  }
}

/* ------------------ Premium Input (matches Guard) ------------------ */

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    required this.textInputAction,
    this.onSubmitted,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
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
