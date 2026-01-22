import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/theme.dart';
import 'core/storage.dart';
import 'services/notification_service.dart';

import 'screens/guard_shell_screen.dart';
import 'screens/resident_shell_screen.dart';
import 'screens/admin_shell_screen.dart';
import 'screens/role_select_screen.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Firebase not configured - continue without notifications
    print("Firebase initialization failed: $e");
  }

  // Initialize notification service
  try {
    await NotificationService().initialize();
  } catch (e) {
    print("Notification service initialization failed: $e");
  }

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
