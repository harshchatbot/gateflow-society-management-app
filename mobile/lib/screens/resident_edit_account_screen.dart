import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../core/app_logger.dart';
import '../services/resident_service.dart';
import '../core/env.dart';
import '../widgets/app_text_field.dart';
import '../ui/app_loader.dart';

/// Edit Account Information Screen
/// 
/// Allows residents to update their name and other account details.
/// Theme: Green/Success theme (matching resident login and dashboard)
class ResidentEditAccountScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String societyId;
  final String flatNo;

  const ResidentEditAccountScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.societyId,
    required this.flatNo,
  });

  @override
  State<ResidentEditAccountScreen> createState() => _ResidentEditAccountScreenState();
}

class _ResidentEditAccountScreenState extends State<ResidentEditAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _residentService = ResidentService(baseUrl: Env.apiBaseUrl);
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.residentName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _residentService.updateProfile(
        residentId: widget.residentId,
        societyId: widget.societyId,
        flatNo: widget.flatNo,
        residentName: _nameController.text.trim(),
      );

      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.i("Account updated successfully");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Account updated successfully",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        AppLogger.e("Failed to update account", error: result.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? "Failed to update account",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      AppLogger.e("Error updating account", error: e);
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
            margin: const EdgeInsets.all(16),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          "Edit Account",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
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
                  // Header Section
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: AppColors.success,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Account Information",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.text,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Update your account details",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.text2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  
                  // Name Input
                  AppTextField(
                    controller: _nameController,
                    label: "Full Name",
                    hint: "Enter your full name",
                    icon: Icons.person_rounded,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Name is required";
                      }
                      if (value.trim().length < 2) {
                        return "Name must be at least 2 characters";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Read-only Info Cards
                  _buildInfoCard(
                    icon: Icons.home_rounded,
                    label: "Flat Number",
                    value: widget.flatNo,
                    iconColor: AppColors.success,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.apartment_rounded,
                    label: "Society ID",
                    value: widget.societyId,
                    iconColor: AppColors.success,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleSave,
                      icon: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: AppLoader.inline(size: 20),
                            )
                          : const Icon(Icons.save_rounded, size: 22),
                      label: Text(
                        _isLoading ? "Saving..." : "Save Changes",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) AppLoader.overlay(showAfter: const Duration(milliseconds: 300), show: true),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.lock_rounded,
            size: 16,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
