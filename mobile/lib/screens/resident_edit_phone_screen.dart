import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/resident_service.dart';
import '../core/env.dart';
import '../widgets/app_text_field.dart';
import '../widgets/primary_button.dart';
import '../ui/glass_loader.dart';

/// Edit Phone Number Screen
/// 
/// Allows residents to update their phone number.
class ResidentEditPhoneScreen extends StatefulWidget {
  final String residentId;
  final String currentPhone;
  final String societyId;
  final String flatNo;

  const ResidentEditPhoneScreen({
    super.key,
    required this.residentId,
    required this.currentPhone,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentEditPhoneScreen> createState() => _ResidentEditPhoneScreenState();
}

class _ResidentEditPhoneScreenState extends State<ResidentEditPhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _residentService = ResidentService(baseUrl: Env.apiBaseUrl);
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text = widget.currentPhone;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Phone number is required";
    }
    final phone = value.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.length < 10) {
      return "Please enter a valid phone number";
    }
    return null;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _residentService.updateProfile(
        residentId: widget.residentId,
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        residentPhone: _phoneController.text.trim(),
      );

      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.i("Phone number updated successfully");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Phone number updated successfully",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).pop(_phoneController.text.trim());
      } else {
        AppLogger.e("Failed to update phone", error: result.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? "Failed to update phone number",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      AppLogger.e("Error updating phone", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "An error occurred. Please try again.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          "Update Phone Number",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.border,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Phone Number",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Update your phone number for notifications",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppTextField(
                    controller: _phoneController,
                    label: "Phone Number",
                    hint: "+91 9876543210",
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    validator: _validatePhone,
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    text: "Update Phone Number",
                    onPressed: _handleSave,
                    isLoading: _isLoading,
                    icon: Icons.save_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) const GlassLoader(),
        ],
      ),
    );
  }
}
