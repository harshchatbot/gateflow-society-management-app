import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme.dart';
import 'core/storage.dart';
import 'screens/guard_login_screen.dart';
import 'screens/new_visitor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env"); // Ensure path is correct for your project
  
  // 1. Get Session Map
  final session = await Storage.getGuardSession();
  
  // 2. Determine Start Screen
  Widget startScreen;
  if (session != null) {
    // Extract values from your Map
    startScreen = NewVisitorScreen(
      guardId: session['guard_id']!,
      guardName: session['guard_name']!,
      societyId: session['society_id']!,
    );
  } else {
    startScreen = const GuardLoginScreen();
  }
  
  runApp(MyApp(initialScreen: startScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GateFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(), // Uses the new Salesforce Theme
      home: initialScreen,
    );
  }
}