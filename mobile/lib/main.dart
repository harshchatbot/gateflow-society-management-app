import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gateflow/core/app_logger.dart';
import 'package:gateflow/core/env.dart';
import 'package:gateflow/core/theme.dart';
import 'package:gateflow/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for guard simplicity
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Load environment variables from .env with logging
  await Env.load();

  runApp(const GateFlowApp());
}

class GateFlowApp extends StatelessWidget {
  const GateFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GateFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
    );
  }
}
