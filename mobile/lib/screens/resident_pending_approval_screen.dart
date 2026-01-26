import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import 'resident_login_screen.dart';
import 'resident_shell_screen.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';

/// Resident Pending Approval Screen
/// 
/// Shown when resident tries to login but their signup is still pending approval
class ResidentPendingApprovalScreen extends StatefulWidget {
  final String email;

  const ResidentPendingApprovalScreen({
    super.key,
    required this.email,
  });

  @override
  State<ResidentPendingApprovalScreen> createState() => _ResidentPendingApprovalScreenState();
}

class _ResidentPendingApprovalScreenState extends State<ResidentPendingApprovalScreen> {
  final FirestoreService _firestore = FirestoreService();
  bool _isChecking = false;

  Future<void> _checkApprovalStatus() async {
    setState(() => _isChecking = true);

    try {
      final membership = await _firestore.getCurrentUserMembership();
      
      if (membership != null) {
        final bool isActive = membership['active'] == true;
        
        if (isActive) {
          // Approved! Navigate to resident shell
          if (!mounted) return;
          
          final societyId = (membership['societyId'] as String?) ?? '';
          final name = (membership['name'] as String?) ?? 'Resident';
          final uid = (membership['uid'] as String?) ?? '';
          final flatNo = (membership['flatNo'] as String?)?.trim() ?? '';
          
          if (societyId.isNotEmpty && uid.isNotEmpty) {
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
            return;
          }
        }
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Your approval is still pending. Please wait for admin approval."),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      AppLogger.e("Error checking approval status", error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Failed to check approval status. Please try again."),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
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
              MaterialPageRoute(builder: (_) => const ResidentLoginScreen()),
            );
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
                    AppColors.success.withOpacity(0.15),
                    AppColors.bg,
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.pending_actions_rounded,
                        color: AppColors.success,
                        size: 60,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      "Pending Approval",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Your resident signup request is pending approval from the admin.",
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.text2,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "You will be able to login once your request is approved.",
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.text2,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.email_rounded, color: AppColors.success, size: 20),
                              const SizedBox(width: 12),
                              const Text(
                                "Email",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.email,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isChecking ? null : _checkApprovalStatus,
                        icon: _isChecking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 20),
                        label: Text(
                          _isChecking ? "CHECKING..." : "CHECK STATUS",
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 16,
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
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const ResidentLoginScreen()),
                          );
                        },
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text(
                          "BACK TO LOGIN",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 16,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                          side: BorderSide(color: AppColors.success, width: 2),
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
          ),
        ],
      ),
    );
  }
}
