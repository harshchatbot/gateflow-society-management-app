import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import 'admin_login_screen.dart';

/// Admin Pending Approval Screen
///
/// Shown when admin tries to login but their signup is still pending approval
///
/// NOTE: Keep constructor param name as `email` for backward compatibility.
/// In OTP flows, pass phone string here (e.g. "+91xxxx") and UI will render it as Contact.
class AdminPendingApprovalScreen extends StatelessWidget {
  final String? email;

  const AdminPendingApprovalScreen({
    super.key,
    this.email,
    required String societyId,
    required String adminId,
    required String adminName,
  });

  bool _looksLikePhone(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    // +91..., or a mostly numeric string
    if (v.startsWith('+')) return true;
    final digits = v.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 10 && digits.length >= (v.length * 0.6);
  }

  String _maskIfPhone(String value) {
    final v = value.trim();
    if (!_looksLikePhone(v)) return v;

    // Mask: +91******1234
    if (v.length <= 6) return v;
    final last4 = v.substring(v.length - 4);
    final prefix = v.startsWith('+') ? v.substring(0, 3) : v.substring(0, 2);
    return '$prefix******$last4';
  }

  @override
  Widget build(BuildContext context) {
    final value = email ?? '';

    final isPhone = _looksLikePhone(value);
    final displayValue = _maskIfPhone(value);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
          // Calm background wash
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.admin.withOpacity(0.12),
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
                    // Icon bubble
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppColors.admin.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.pending_actions_rounded,
                        color: AppColors.admin,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 22),

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
                    const SizedBox(height: 14),

                    // Status banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.admin.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.admin.withOpacity(0.18)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_rounded,
                              color: AppColors.admin, size: 18),
                          SizedBox(width: 8),
                          Text(
                            "Waiting for Super Admin approval",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.admin,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                    const Text(
                      "Your admin access request has been submitted.\nYou’ll be able to login once it’s approved.",
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.text2,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 26),

                    // Timeline (calm, MyGate-ish)
                    _TimelineCard(),

                    const SizedBox(height: 18),

                    // Contact Card (email or phone)
                    Container(
                      padding: const EdgeInsets.all(18),
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
                              Icon(
                                isPhone
                                    ? Icons.phone_rounded
                                    : Icons.email_rounded,
                                color: AppColors.admin,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isPhone ? "Contact" : "Email",
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            displayValue,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPhone
                                ? "This phone is used to verify your identity."
                                : "This email was used for your request.",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text2,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const AdminLoginScreen()),
                          );
                        },
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text(
                          "BACK TO LOGIN",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.admin,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Tip: If it takes too long, contact your Super Admin.",
                      style: TextStyle(
                        color: AppColors.text2.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    )
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

class _TimelineCard extends StatelessWidget {
  const _TimelineCard();

  Widget _step({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success.withOpacity(0.18)
                : AppColors.admin.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: done
                  ? AppColors.success.withOpacity(0.28)
                  : AppColors.admin.withOpacity(0.18),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: done ? AppColors.success : AppColors.admin,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _step(
            icon: Icons.task_alt_rounded,
            title: "Request submitted",
            subtitle: "We’ve shared your admin request with the Super Admin.",
            done: true,
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.border.withOpacity(0.9)),
          const SizedBox(height: 14),
          _step(
            icon: Icons.verified_user_rounded,
            title: "Approval pending",
            subtitle: "Super Admin will review and approve your access.",
            done: false,
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.border.withOpacity(0.9)),
          const SizedBox(height: 14),
          _step(
            icon: Icons.login_rounded,
            title: "Login enabled",
            subtitle: "Once approved, you can login and manage your society.",
            done: false,
          ),
        ],
      ),
    );
  }
}
