import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Keep this for FCM
import 'firebase_options.dart'; // <--- The generated file

import 'ui/sentinel_theme.dart';
import 'services/notification_service.dart';

import 'screens/app_bootstrap_screen.dart';


// Background message handler (must be top-level)
// IMPORTANT: This function must be defined at the top-level (not inside a class)
// so that it can be invoked when the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); // Initialize Firebase in background handler
  if (kDebugMode) {
    debugPrint("Handling a background message: ${message.messageId}");
  }
  // You can process the message here, e.g., show a local notification
  // For example: NotificationService().showNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Always call this first

  // Load environment variables
  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    if (kDebugMode) {
      debugPrint("Warning: Could not load .env file: $e");
    }
  }

  // Initialize Firebase App
  // This is crucial for FCM and other Firebase services
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kDebugMode) {
      debugPrint("Firebase initialized successfully.");
    }

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize notification service AFTER Firebase is initialized
    await NotificationService().initialize();
    if (kDebugMode) {
      debugPrint("Notification service initialized.");
    }

  } catch (e) {
    if (kDebugMode) {
      debugPrint("Firebase initialization failed: $e");
      debugPrint("Skipping notification service initialization (Firebase not available)");
    }
  }


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sentinel',
      debugShowCheckedModeBanner: false,
      theme: SentinelTheme.light(),
      home: const AppBootstrapScreen(),
    );
  }
}
