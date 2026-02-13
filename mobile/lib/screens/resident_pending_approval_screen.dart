import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import '../widgets/sentinel_illustration.dart';

///import 'resident_login_screen.dart';
import 'resident_shell_screen.dart';
import 'find_society_screen.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'onboarding_choose_role_screen.dart';

/// Resident Pending Approval Screen
///
/// Shown when resident tries to login but their signup is still pending approval
///
/// NOTE: Keep constructor param name as `email` for backward compatibility.
/// In OTP flows, pass phone string here (e.g. "+91xxxx") and UI will render it as Contact.
class ResidentPendingApprovalScreen extends StatefulWidget {
  // Backward compatible "email" param: can hold phone or email or any contact string
  final String? email;

  // New required identity context (needed for routing + better UX)
  final String residentId;
  final String societyId;
  final String residentName;

  const ResidentPendingApprovalScreen({
    super.key,
    this.email,
    required this.residentId,
    required this.societyId,
    required this.residentName,
  });

  @override
  State<ResidentPendingApprovalScreen> createState() =>
      _ResidentPendingApprovalScreenState();
}

class _ResidentPendingApprovalScreenState
    extends State<ResidentPendingApprovalScreen> {
  final FirestoreService _firestore = FirestoreService();
  bool _isChecking = false;
  bool _canFindSocietyAgain = false;

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

    // Mask: +91******1234 OR 98******1234
    if (v.length <= 6) return v;
    final last4 = v.substring(v.length - 4);
    final prefix = v.startsWith('+') ? v.substring(0, 3) : v.substring(0, 2);
    return '$prefix******$last4';
  }

  Future<void> _checkApprovalStatus() async {
    setState(() => _isChecking = true);

    try {
      final membership = await _firestore.getCurrentUserMembership();

      // If approved, route to ResidentShell
      if (membership != null && membership['active'] == true) {
        if (!mounted) return;

        final societyId = (membership['societyId'] as String?) ?? '';
        final name = (membership['name'] as String?) ?? widget.residentName;
        final uid = (membership['uid'] as String?) ?? widget.residentId;
        final flatNo = (membership['flatNo'] as String?)?.trim() ?? '';

        if (societyId.isNotEmpty && uid.isNotEmpty) {
          await Storage.clearResidentJoinSocietyId();
          if (!mounted) return;

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

      // If join request exists and is rejected, allow finding society again
      final pendingSocietyId = await Storage.getResidentJoinSocietyId();
      if (pendingSocietyId != null) {
        final jr = await _firestore.getResidentJoinRequest(
          societyId: pendingSocietyId,
        );

        if (jr != null) {
          final status = (jr['status'] as String?) ?? 'PENDING';

          if (status == 'REJECTED') {
            if (!mounted) return;
            setState(() => _canFindSocietyAgain = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Your join request was rejected. You can try again.",
                ),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Your request is still pending approval."),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e, st) {
      AppLogger.e("Error checking approval status", error: e, stackTrace: st);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _logoutToChooseRole() async {
    try {
      await FirebaseAuth.instance.signOut();
      await Storage.clearResidentJoinSocietyId();
    } catch (e, st) {
      AppLogger.e("Logout failed", error: e, stackTrace: st);
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingChooseRoleScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface),
          onPressed: _logoutToChooseRole,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            _buildPendingBanner(theme),
            const SizedBox(height: 14),

            // ✅ Identity / Contact Card (OTP-first friendly)
            _buildContactCard(theme),
            const SizedBox(height: 22),

            /// Illustration (dimmed like MyGate)
            const Opacity(
              opacity: 0.42,
              child: SentinelIllustration(kind: 'pending'),
            ),

            const SizedBox(height: 28),
            _buildTimeline(theme),

            const SizedBox(height: 32),
            _buildPrimaryActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            "Approval Pending",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your account needs approval from your society admin to ensure only verified residents get access.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(ThemeData theme) {
    final raw = widget.email?.trim() ?? '';
    final isPhone = _looksLikePhone(raw);
    final display = _maskIfPhone(raw);

    final name = widget.residentName.trim().isNotEmpty
        ? widget.residentName.trim()
        : 'Resident';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isPhone ? Icons.phone_rounded : Icons.email_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  display.isEmpty ? "Phone login" : display,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Society: ${widget.societyId}",
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(ThemeData theme) {
    Widget step(
      bool done,
      String title,
      String subtitle,
    ) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        step(
          true,
          "Application submitted",
          "Your request has been sent to the society admin.",
        ),
        const SizedBox(height: 16),
        step(
          true,
          "We’re reminding",
          "Admins receive reminders every 24 hours.",
        ),
        const SizedBox(height: 16),
        step(
          false,
          "Verification by admin",
          "Most approvals happen within 72 hours.",
        ),
      ],
    );
  }

  Widget _buildPrimaryActions(ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton(
            onPressed: _isChecking ? null : _checkApprovalStatus,
            child: _isChecking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    "CHECK STATUS",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _logoutToChooseRole,
            child: const Text(
              "LOGOUT",
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (_canFindSocietyAgain) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await Storage.clearResidentJoinSocietyId();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const FindSocietyScreen()),
                );
              },
              child: const Text(
                "FIND SOCIETY AGAIN",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
