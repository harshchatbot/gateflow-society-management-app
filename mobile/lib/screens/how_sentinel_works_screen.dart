import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

/// Static pre-signup info screen: "How Sentinel Works".
/// Explains onboarding in 4–5 steps and highlights SOS as a USP.
/// No backend; accessible from RoleSelectScreen.
class HowSentinelWorksScreen extends StatelessWidget {
  const HowSentinelWorksScreen({super.key});

  static const List<Map<String, String>> _steps = [
    {
      'title': '1. Choose your role',
      'body': 'Guard, Resident, or Admin. Each role has a tailored flow.',
    },
    {
      'title': '2. Join or create society',
      'body': 'Residents and Admins enter a society code. Guards join via QR from Admin.',
    },
    {
      'title': '3. Get approved (Resident/Admin)',
      'body': 'Society admin approves your request. Guards join using a 6-digit admin code with expiry.',
    },
    {
      'title': '4. Use your dashboard',
      'body': 'Guards log visitors; Residents approve/reject; Admins manage society, notices & complaints.',
    },
    {
      'title': '5. Emergency SOS',
      'body': 'Residents can send an instant SOS alert. Guards and Admins see and respond to emergencies right away.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'How Sentinel Works',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Onboarding in a few steps',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 20),
            ..._steps.map((step) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step['title']!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          step['body']!,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.text2,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.sos_rounded, color: AppColors.error, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SOS alerts go to your society\'s security and admin instantly—so help is always one tap away.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
