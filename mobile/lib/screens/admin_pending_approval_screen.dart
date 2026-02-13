import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'phone_otp_login_screen.dart';

/// Admin Pending Approval Screen
///
/// Shown when admin tries to login but their request is still pending approval.
///
/// NOTE: Keep constructor param name as `email` for backward compatibility.
/// In OTP flows, pass phone string here (e.g. "+91xxxx") and UI will render it as Contact.
class AdminPendingApprovalScreen extends StatelessWidget {
  final String societyId;
  final String adminId;
  final String adminName;

  /// Backward compatible param:
  /// - legacy: email
  /// - OTP: phone in this field
  final String? email;
  final String? title;
  final String? badgeText;
  final String? message;
  final String? timelineStep1Subtitle;
  final String? timelineStep2Title;
  final String? timelineStep2Subtitle;
  final String? timelineStep3Subtitle;
  final String? tipText;

  const AdminPendingApprovalScreen({
    super.key,
    required this.societyId,
    required this.adminId,
    required this.adminName,
    this.email,
    this.title,
    this.badgeText,
    this.message,
    this.timelineStep1Subtitle,
    this.timelineStep2Title,
    this.timelineStep2Subtitle,
    this.timelineStep3Subtitle,
    this.tipText,
  });

  bool _looksLikePhone(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
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

  Future<void> _logoutAndRevealLogin(BuildContext context) async {
    // Make this behave exactly like a Logout button.
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Ignore signOut errors; still route to login.
    }

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const PhoneOtpLoginScreen(roleHint: 'admin'),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = email ?? '';
    final isPhone = _looksLikePhone(value);
    final displayValue = _maskIfPhone(value);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: cs.onSurface,
              size: 20,
            ),
          ),
          onPressed: () => _logoutAndRevealLogin(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.12),
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor,
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
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.pending_actions_rounded,
                        color: cs.primary,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title ?? "Pending Approval",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: cs.primary.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_rounded,
                              color: cs.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            badgeText ?? "Waiting for Super Admin approval",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      message ??
                          "Hi ${adminName.isNotEmpty ? adminName : 'Admin'}, your admin access request has been submitted.\nYou’ll be able to login once it’s approved.",
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurface.withValues(alpha: 0.72),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),
                    _TimelineCard(
                      step1Subtitle: timelineStep1Subtitle,
                      step2Title: timelineStep2Title,
                      step2Subtitle: timelineStep2Subtitle,
                      step3Subtitle: timelineStep3Subtitle,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.dividerColor),
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
                                color: cs.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isPhone ? "Contact" : "Email",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            displayValue,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPhone
                                ? "This phone is used to verify your identity."
                                : "This email was used for your request.",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.68),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.apartment_rounded, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Society ID: $societyId",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _logoutAndRevealLogin(context),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        label: const Text(
                          "LOGOUT",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tipText ??
                          "Tip: If it takes too long, contact your Super Admin.",
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.68),
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
  final String? step1Subtitle;
  final String? step2Title;
  final String? step2Subtitle;
  final String? step3Subtitle;

  const _TimelineCard({
    this.step1Subtitle,
    this.step2Title,
    this.step2Subtitle,
    this.step3Subtitle,
  });

  Widget _step({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: done
                ? Colors.green.withValues(alpha: 0.18)
                : cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: done
                  ? Colors.green.withValues(alpha: 0.28)
                  : cs.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: done ? Colors.green.shade700 : cs.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          _step(
            context: context,
            icon: Icons.task_alt_rounded,
            title: "Request submitted",
            subtitle: step1Subtitle ??
                "We’ve shared your admin request with the Super Admin.",
            done: true,
          ),
          const SizedBox(height: 14),
          Divider(color: theme.dividerColor.withValues(alpha: 0.9)),
          const SizedBox(height: 14),
          _step(
            context: context,
            icon: Icons.verified_user_rounded,
            title: step2Title ?? "Approval pending",
            subtitle: step2Subtitle ??
                "Super Admin will review and approve your access.",
            done: false,
          ),
          const SizedBox(height: 14),
          Divider(color: theme.dividerColor.withValues(alpha: 0.9)),
          const SizedBox(height: 14),
          _step(
            context: context,
            icon: Icons.login_rounded,
            title: "Login enabled",
            subtitle: step3Subtitle ??
                "Once approved, you can login and manage your society.",
            done: false,
          ),
        ],
      ),
    );
  }
}
