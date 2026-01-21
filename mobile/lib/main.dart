import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme.dart';
import 'core/storage.dart';
import 'screens/guard_login_screen.dart';
import 'screens/guard_shell_screen.dart'; // Correct relative path

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env"); 
  
  final session = await Storage.getGuardSession();
  
  Widget startScreen;
  if (session != null) {
    startScreen = GuardShellScreen(
      guardId: session['guard_id'] ?? 'Unknown',
      guardName: session['guard_name'] ?? 'Guard',
      societyId: session['society_id'] ?? 'Society',
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
      theme: AppTheme.light(), 
      home: initialScreen,
    );
  }
}