import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/theme.dart';
import 'core/storage.dart';

import 'screens/guard_shell_screen.dart';
import 'screens/resident_shell_screen.dart';
import 'screens/admin_shell_screen.dart';
import 'screens/role_select_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load env (API base URL etc.)
  await dotenv.load(fileName: "assets/.env");

  // Check saved sessions
  final residentSession = await Storage.getResidentSession();
  final guardSession = await Storage.getGuardSession();
  final adminSession = await Storage.getAdminSession();

  Widget startScreen;

  // 1️⃣ Resident session has highest priority
  if (residentSession != null) {
    startScreen = ResidentShellScreen(
      residentId: residentSession.residentId,
      residentName: residentSession.residentName,
      societyId: residentSession.societyId,
      flatNo: residentSession.flatNo,
    );
  }
  // 2️⃣ Guard session
  else if (guardSession != null) {
    startScreen = GuardShellScreen(
      guardId: guardSession.guardId,
      guardName: guardSession.guardName.isNotEmpty
          ? guardSession.guardName
          : "Guard",
      societyId: guardSession.societyId.isNotEmpty
          ? guardSession.societyId
          : "Society",
    );
  }
  // 3️⃣ Admin session
  else if (adminSession != null) {
    startScreen = AdminShellScreen(
      adminId: adminSession.adminId,
      adminName: adminSession.adminName,
      societyId: adminSession.societyId,
      role: adminSession.role,
    );
  }
  // 4️⃣ No session → role selection
  else {
    startScreen = const RoleSelectScreen();
  }

  runApp(MyApp(initialScreen: startScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({
    super.key,
    required this.initialScreen,
  });

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
