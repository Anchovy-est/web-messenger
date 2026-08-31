import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Which chat a notification should open, if any.
String? chatIdFromNotificationData(Map<String, dynamic> data) {
  if (data['type'] != 'message') return null;
  return data['chatId'] as String?;
}

/// Wraps FCM (receiving pushes) and flutter_local_notifications
/// (showing one while the app is foregrounded). Every method degrades
/// to a no-op when this device has no Firebase configuration.
class PushNotificationService {
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _chatIdToOpenController = StreamController<String>.broadcast();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  bool _initialized = false;

  /// True once Firebase has actually initialized.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  /// Fires with a chatId whenever a notification is tapped.
  Stream<String> get chatIdToOpen => _chatIdToOpenController.stream;

  /// Test-only hook to simulate a notification tap.
  @visibleForTesting
  void debugEmitChatIdToOpen(String chatId) =>
      _chatIdToOpenController.add(chatId);

  /// Sets up foreground/tapped-notification handling. Safe to call
  /// unconditionally; a no-op without Firebase. Idempotent.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!isAvailable) return;

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final chatId = response.payload;
        if (chatId != null) _chatIdToOpenController.add(chatId);
      },
    );

    // A foreground push gets no automatic system notification, so show
    // one ourselves.
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    // Tapped while backgrounded.
    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
    // Tapped while fully killed — the tap launches the app, so this is
    // polled once at startup.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleOpenedMessage(initialMessage);
  }

  /// Requests notification permission and returns this device's FCM
  /// token, or null if denied or unconfigured.
  Future<String?> requestPermissionAndGetToken() async {
    if (!isAvailable) return null;
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    return FirebaseMessaging.instance.getToken();
  }

  /// The current token without prompting for permission.
  Future<String?> getCurrentToken() async {
    if (!isAvailable) return null;
    return FirebaseMessaging.instance.getToken();
  }

  /// Fires when Firebase rotates this device's token.
  Stream<String> get onTokenRefresh => isAvailable
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream.empty();

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final chatId = chatIdFromNotificationData(message.data);
    unawaited(
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'New messages and chat invitations',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: chatId,
      ),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final chatId = chatIdFromNotificationData(message.data);
    if (chatId != null) _chatIdToOpenController.add(chatId);
  }

  void dispose() {
    unawaited(_foregroundSubscription?.cancel());
    unawaited(_openedAppSubscription?.cancel());
    unawaited(_chatIdToOpenController.close());
  }
}
