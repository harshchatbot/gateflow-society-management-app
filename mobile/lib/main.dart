import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Keep this for FCM
import 'firebase_options.dart'; // <--- The generated file

import 'core/theme.dart';
import 'core/storage.dart';
import 'services/notification_service.dart'; // Your notification service

import 'screens/guard_shell_screen.dart';
import 'screens/resident_shell_screen.dart';
import 'screens/admin_shell_screen.dart';
import 'screens/role_select_screen.dart';

// Background message handler (must be top-level)
// IMPORTANT: This function must be defined at the top-level (not inside a class)
// so that it can be invoked when the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); // Initialize Firebase in background handler
  print("Handling a background message: ${message.messageId}");
  // You can process the message here, e.g., show a local notification
  // For example: NotificationService().showNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Always call this first

  // Load environment variables
  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    print("Warning: Could not load .env file: $e");
  }

  // Initialize Firebase App
  // This is crucial for FCM and other Firebase services
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("Firebase initialized successfully.");

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize notification service AFTER Firebase is initialized
    await NotificationService().initialize();
    print("Notification service initialized.");

  } catch (e) {
    print("Firebase initialization failed: $e");
    print("Skipping notification service initialization (Firebase not available)");
  }


  // Determine the initial screen based on sessions
  Widget startScreen;
  final residentSession = await Storage.getResidentSession();
  final guardSession = await Storage.getGuardSession();
  final adminSession = await Storage.getAdminSession();

  if (residentSession != null) {
    startScreen = ResidentShellScreen(
      residentId: residentSession.residentId,
      residentName: residentSession.residentName,
      societyId: residentSession.societyId,
      flatNo: residentSession.flatNo,
    );
  } else if (guardSession != null) {
    startScreen = GuardShellScreen(
      guardId: guardSession.guardId,
      guardName: guardSession.guardName.isNotEmpty
          ? guardSession.guardName
          : "Guard",
      societyId: guardSession.societyId.isNotEmpty
          ? guardSession.societyId
          : "Society",
    );
  } else if (adminSession != null) {
    startScreen = AdminShellScreen(
      adminId: adminSession.adminId,
      adminName: adminSession.adminName,
      societyId: adminSession.societyId,
      role: adminSession.role,
    );
  } else {
    startScreen = const RoleSelectScreen();
  }

  // Run your app with the determined startScreen
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
