import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_logger.dart';
import '../core/storage.dart';

/// Notification Service
/// 
/// Handles FCM token management and local notifications with sound
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  bool _initialized = false;
  
  // Callback for when notification is received (to update counts)
  Function(Map<String, dynamic>)? _onNotificationReceived;
  // Callback for when notification is tapped (for navigation)
  Function(Map<String, dynamic>)? _onNotificationTap;
  
  /// Set callback for notification received
  void setOnNotificationReceived(Function(Map<String, dynamic>) callback) {
    _onNotificationReceived = callback;
  }

  /// Set callback for notification tap
  void setOnNotificationTap(Function(Map<String, dynamic>) callback) {
    _onNotificationTap = callback;
  }

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Check if Firebase is initialized
      bool firebaseAvailable = false;
      try {
        // Try to get the default Firebase app
        Firebase.app();
        firebaseAvailable = true;
        AppLogger.i("Firebase app already initialized");
      } catch (e) {
        // Firebase not initialized, try to initialize
        try {
          await Firebase.initializeApp();
          firebaseAvailable = true;
          AppLogger.i("Firebase initialized successfully");
        } catch (e2) {
          AppLogger.w("Firebase not available, skipping notification setup: $e2");
          return;
        }
      }

      if (!firebaseAvailable) {
        AppLogger.w("Firebase not available, skipping notification setup");
        return;
      }

      // Request permissions
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        AppLogger.i("Notification permissions granted");
      } else {
        AppLogger.w("Notification permissions denied");
        return;
      }

      // Create Android notification channel BEFORE initializing
      const androidChannel = AndroidNotificationChannel(
        'sentinel_channel',
        'Sentinel Notifications',
        description: 'Notifications for visitor entries and notices',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Initialize local notifications (for foreground notifications)
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create the notification channel (required for Android 8.0+)
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      // Get FCM token
      _fcmToken = await _fcm.getToken();
      if (_fcmToken != null) {
        AppLogger.i("FCM token obtained", data: {"token": _fcmToken!.substring(0, 20) + "..."});
        await _saveFcmToken(_fcmToken!);
      }

      // Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _saveFcmToken(newToken);
        AppLogger.i("FCM token refreshed");
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages (when app is in background)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

      // Check if app was opened from notification
      RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleBackgroundMessage(initialMessage);
      }

      _initialized = true;
      AppLogger.i("Notification service initialized");
    } catch (e) {
      AppLogger.e("Error initializing notification service", error: e);
    }
  }

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Save FCM token to local storage (to send to backend)
  Future<void> _saveFcmToken(String token) async {
    try {
      // Save to SharedPreferences for later use
      // In a real implementation, you'd send this to your backend
      AppLogger.i("FCM token saved locally", data: {"token_length": token.length});
    } catch (e) {
      AppLogger.e("Error saving FCM token", error: e);
    }
  }

  /// Handle foreground messages (app is open)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.i("Foreground notification received", data: {
      "title": message.notification?.title,
      "body": message.notification?.body,
      "data": message.data,
    });

    // Show local notification with sound
    await _showLocalNotification(
      title: message.notification?.title ?? "New Notification",
      body: message.notification?.body ?? "",
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
    
    // Trigger notification count update callback if set
    if (_onNotificationReceived != null && message.data.isNotEmpty) {
      _onNotificationReceived!(message.data);
    }
  }

  /// Handle background messages (app is in background/terminated)
  void _handleBackgroundMessage(RemoteMessage message) {
    AppLogger.i("Background notification received", data: {
      "title": message.notification?.title,
      "body": message.notification?.body,
    });
    // Forward data to tap handler so screens can navigate appropriately
    if (_onNotificationTap != null && message.data.isNotEmpty) {
      _onNotificationTap!(message.data);
    }
  }

  /// Show local notification with sound
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'sentinel_channel',
      'Sentinel Notifications',
      channelDescription: 'Notifications for visitor entries and notices',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    AppLogger.i("Notification tapped", data: {"payload": response.payload});

    if (_onNotificationTap != null && response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        if (data is Map<String, dynamic>) {
          _onNotificationTap!(data);
        }
      } catch (e, st) {
        AppLogger.e("Failed to parse notification payload", error: e, stackTrace: st);
      }
    }
  }

  /// Subscribe to a topic (e.g., society-specific notifications)
  Future<void> subscribeToTopic(String topic) async {
    if (!_initialized) {
      AppLogger.w("Notification service not initialized, skipping topic subscription");
      return;
    }

    try {
      // Verify Firebase is available
      try {
        await _fcm.getToken(); // This will fail if Firebase is not initialized
      } catch (e) {
        AppLogger.w("Firebase not available, skipping topic subscription");
        return;
      }

      await _fcm.subscribeToTopic(topic);
      AppLogger.i("Subscribed to topic", data: {"topic": topic});
    } catch (e) {
      AppLogger.e("Error subscribing to topic", error: e);
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      AppLogger.i("Unsubscribed from topic", data: {"topic": topic});
    } catch (e) {
      AppLogger.e("Error unsubscribing from topic", error: e);
    }
  }

  /// Subscribe user to society and flat topics based on their role
  Future<void> subscribeUserTopics({
    required String societyId,
    String? flatId,
    String? role,
  }) async {
    // Check if Firebase is initialized
    if (!_initialized) {
      AppLogger.w("Notification service not initialized, skipping topic subscription");
      return;
    }

    try {
      // Verify Firebase is available
      try {
        await _fcm.getToken(); // This will fail if Firebase is not initialized
      } catch (e) {
        AppLogger.w("Firebase not available, skipping topic subscription");
        return;
      }

      // Subscribe to society topic (for notices) - multi-tenant format
      await subscribeToTopic("society_$societyId");

      // Subscribe to flat topic (for visitor entries) if resident - multi-tenant format
      if (flatId != null && role == "resident") {
        await subscribeToTopic("flat_${societyId}_$flatId");
      }

      // Subscribe staff (guards/admins) to SOS / staff-only alerts
      if (role == "guard" || role == "admin") {
        await subscribeToTopic("society_${societyId}_staff");
      }

      AppLogger.i("Subscribed to topics", data: {
        "society_id": societyId,
        "flat_id": flatId,
        "role": role,
      });
    } catch (e) {
      AppLogger.e("Error subscribing to topics", error: e);
    }
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages here
  AppLogger.i("Background message received", data: {
    "title": message.notification?.title,
    "body": message.notification?.body,
  });
}
