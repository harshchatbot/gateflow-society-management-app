import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_logger.dart';

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
  AuthorizationStatus? _authorizationStatus;
  final Set<String> _subscribedTopics = <String>{};
  StreamSubscription<User?>? _authStateSubscription;

  String _topicKey(String raw) {
    final cleaned = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    return cleaned.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }
  
  final Map<String, Function(Map<String, dynamic>)> _onNotificationReceivedListeners =
      <String, Function(Map<String, dynamic>)>{};
  final Map<String, Function(Map<String, dynamic>)> _onNotificationTapListeners =
      <String, Function(Map<String, dynamic>)>{};
  
  /// Set callback for notification received
  void setOnNotificationReceived(Function(Map<String, dynamic>) callback) {
    registerOnNotificationReceived('default', callback);
  }

  /// Set callback for notification tap
  void setOnNotificationTap(Function(Map<String, dynamic>) callback) {
    registerOnNotificationTap('default', callback);
  }

  void registerOnNotificationReceived(
    String listenerId,
    Function(Map<String, dynamic>) callback,
  ) {
    _onNotificationReceivedListeners[listenerId] = callback;
  }

  void unregisterOnNotificationReceived(String listenerId) {
    _onNotificationReceivedListeners.remove(listenerId);
  }

  void registerOnNotificationTap(
    String listenerId,
    Function(Map<String, dynamic>) callback,
  ) {
    _onNotificationTapListeners[listenerId] = callback;
  }

  void unregisterOnNotificationTap(String listenerId) {
    _onNotificationTapListeners.remove(listenerId);
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
      _authorizationStatus = settings.authorizationStatus;

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        AppLogger.i("Notification permissions granted", data: {
          "authorization_status": settings.authorizationStatus.name,
        });
      } else {
        AppLogger.w("Notification permissions denied", data: {
          "authorization_status": settings.authorizationStatus.name,
        });
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

      // Get FCM token (may fail with TOO_MANY_REGISTRATIONS during development)
      try {
        _fcmToken = await _fcm.getToken();
        if (_fcmToken != null) {
          AppLogger.i("FCM token obtained", data: {"token": "${_fcmToken!.substring(0, 20)}..."});
          await _saveFcmToken(_fcmToken!);
        }

        // Listen for token refresh
        _fcm.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          _saveFcmToken(newToken);
          AppLogger.i("FCM token refreshed");
        });
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('TOO_MANY_REGISTRATIONS') || msg.contains('too_many_registrations')) {
          AppLogger.w(
            "FCM token temporarily unavailable: too many registrations on this device. "
            "Push will work again after some time or after clearing app data. Local notifications will still work.",
          );
          // Continue: local notifications and message handlers still work
        } else {
          rethrow;
        }
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages (when app is in background)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

      // Check if app was opened from notification
      RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleBackgroundMessage(initialMessage);
      }

      _authStateSubscription?.cancel();
      _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (user) async {
          if (user == null && _subscribedTopics.isNotEmpty) {
            await clearAllTopicSubscriptions();
            AppLogger.i("Cleared FCM topic subscriptions after logout");
          }
        },
      );

      _initialized = true;
      AppLogger.i("Notification service initialized");
    } catch (e) {
      AppLogger.e("Error initializing notification service", error: e);
    }
  }

  /// Get current FCM token
  String? get fcmToken => _fcmToken;
  AuthorizationStatus? get authorizationStatus => _authorizationStatus;
  List<String> get subscribedTopics => _subscribedTopics.toList(growable: false);

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
      "from": message.from,
      "messageId": message.messageId,
    });

    final callbackData = message.data.isNotEmpty
        ? message.data
        : <String, dynamic>{
            'type': '__refresh__',
            'source': 'fcm_notification_only',
          };

    // Show local notification with sound
    await _showLocalNotification(
      title: message.notification?.title ?? "New Notification",
      body: message.notification?.body ?? "",
      payload: jsonEncode(callbackData),
    );
    
    _notifyReceived(callbackData);
  }

  /// Handle background messages (app is in background/terminated)
  void _handleBackgroundMessage(RemoteMessage message) {
    AppLogger.i("Background notification received", data: {
      "title": message.notification?.title,
      "body": message.notification?.body,
      "data": message.data,
      "from": message.from,
      "messageId": message.messageId,
    });
    final callbackData = message.data.isNotEmpty
        ? message.data
        : <String, dynamic>{
            'type': '__refresh__',
            'source': 'fcm_notification_only',
          };
    _notifyTap(callbackData);
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

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        if (data is Map<String, dynamic>) {
          _notifyTap(data);
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
      _subscribedTopics.add(topic);
      AppLogger.i("Subscribed to topic", data: {"topic": topic});
    } catch (e) {
      AppLogger.e("Error subscribing to topic", error: e);
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      _subscribedTopics.remove(topic);
      AppLogger.i("Unsubscribed from topic", data: {"topic": topic});
    } catch (e) {
      AppLogger.e("Error unsubscribing from topic", error: e);
    }
  }

  Future<void> clearAllTopicSubscriptions() async {
    final topics = _subscribedTopics.toList(growable: false);
    for (final topic in topics) {
      await unsubscribeFromTopic(topic);
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

      final societyKey = _topicKey(societyId);
      final flatKey = flatId != null ? _topicKey(flatId) : null;
      final desiredTopics = <String>{"society_$societyKey"};

      if (flatKey != null && flatKey.isNotEmpty && role == "resident") {
        desiredTopics.add("flat_${societyKey}_$flatKey");
      }

      if (role == "guard" || role == "admin") {
        desiredTopics.add("society_${societyKey}_staff");
      }

      final staleTopics = _subscribedTopics.difference(desiredTopics).toList();
      for (final topic in staleTopics) {
        await unsubscribeFromTopic(topic);
      }

      final missingTopics = desiredTopics.difference(_subscribedTopics).toList();
      for (final topic in missingTopics) {
        await subscribeToTopic(topic);
      }

      AppLogger.i("Subscribed to topics", data: {
        "society_id": societyId,
        "flat_id": flatId,
        "society_key": societyKey,
        "flat_key": flatKey,
        "role": role,
        "topics": _subscribedTopics.toList(growable: false),
        "authorization_status": _authorizationStatus?.name,
        "token_prefix": _fcmToken != null && _fcmToken!.length > 20
            ? _fcmToken!.substring(0, 20)
            : _fcmToken,
      });
    } catch (e) {
      AppLogger.e("Error subscribing to topics", error: e);
    }
  }

  void _notifyReceived(Map<String, dynamic> data) {
    final listeners = List<Function(Map<String, dynamic>)>.from(
      _onNotificationReceivedListeners.values,
    );
    for (final listener in listeners) {
      try {
        listener(data);
      } catch (e, st) {
        AppLogger.e("Notification receive listener failed",
            error: e, stackTrace: st);
      }
    }
  }

  void _notifyTap(Map<String, dynamic> data) {
    final listeners = List<Function(Map<String, dynamic>)>.from(
      _onNotificationTapListeners.values,
    );
    for (final listener in listeners) {
      try {
        listener(data);
      } catch (e, st) {
        AppLogger.e("Notification tap listener failed",
            error: e, stackTrace: st);
      }
    }
  }

  Map<String, dynamic> getDebugSnapshot() {
    return {
      "initialized": _initialized,
      "authorization_status": _authorizationStatus?.name ?? "unknown",
      "token_prefix": _fcmToken != null && _fcmToken!.length > 20
          ? "${_fcmToken!.substring(0, 20)}..."
          : _fcmToken,
      "topics": _subscribedTopics.toList(growable: false),
    };
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
