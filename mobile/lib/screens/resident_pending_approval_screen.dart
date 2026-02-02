import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../widgets/sentinel_illustration.dart';
import 'resident_login_screen.dart';
import 'resident_shell_screen.dart';
import 'find_society_screen.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/storage.dart';

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
  bool _canFindSocietyAgain = false;

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
            // Clear any stored pending join society since we're active now.
            await Storage.clearResidentJoinSocietyId();

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

      // No active membership yet: check join request status if we know the societyId.
      final pendingSocietyId = await Storage.getResidentJoinSocietyId();
      if (pendingSocietyId != null) {
        final jr = await _firestore.getResidentJoinRequest(
          societyId: pendingSocietyId,
        );
        if (jr != null) {
          final status = (jr['status'] as String?) ?? 'PENDING';
          if (status == 'APPROVED') {
            // Try once more to see if membership is active now.
            final refreshed = await _firestore.getCurrentUserMembership();
            if (refreshed != null && refreshed['active'] == true) {
              if (!mounted) return;
              final societyId = (refreshed['societyId'] as String?) ?? '';
              final name = (refreshed['name'] as String?) ?? 'Resident';
              final uid = (refreshed['uid'] as String?) ?? '';
              final flatNo =
                  (refreshed['flatNo'] as String?)?.trim() ?? '';

              if (societyId.isNotEmpty && uid.isNotEmpty) {
                await Storage.clearResidentJoinSocietyId();
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

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Your request is approved. Finalizing access… please try again in a few seconds.",
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          if (status == 'REJECTED') {
            if (!mounted) return;
            setState(() {
              _canFindSocietyAgain = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Your join request was rejected. You can try finding your society again.",
                ),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          // PENDING
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Your join request is pending approval from the admin.",
              ),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            const SizedBox(height: 24),
            const SentinelIllustration(kind: 'pending'),
            const SizedBox(height: 28),
            Text(
              "You're almost in",
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              "Your access request has been sent to the society admin.\nYou'll be notified once it's approved.",
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary.withOpacity(0.4),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.email_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Email",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isChecking ? null : _checkApprovalStatus,
                icon: _isChecking
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary.withOpacity(0.8),
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
              ),
            ),
            const SizedBox(height: 12),
            if (_canFindSocietyAgain)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () async {
                    await Storage.clearResidentJoinSocietyId();
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const FindSocietyScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "FIND SOCIETY AGAIN",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            if (_canFindSocietyAgain) const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
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
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
