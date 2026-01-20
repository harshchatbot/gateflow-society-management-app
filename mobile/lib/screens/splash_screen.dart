import 'package:flutter/material.dart';
import '../core/storage.dart';
import 'guard_login_screen.dart';
import 'new_visitor_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Small delay for splash effect
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final hasSession = await Storage.hasGuardSession();

    if (!mounted) return;

    if (hasSession) {
      final session = await Storage.getGuardSession();
      if (session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => NewVisitorScreen(
              guardId: session['guard_id']!,
              guardName: session['guard_name']!,
              societyId: session['society_id']!,
            ),
          ),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const GuardLoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.security,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              'GateFlow',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
