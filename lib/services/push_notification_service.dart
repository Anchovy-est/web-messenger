import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Which chat a notification's `data` payload should open, if any — a
/// message notification opens that chat; an invitation notification (no
/// `chatId` yet, since the chat isn't accepted) opens nothing more
/// specific than the app itself. Pulled out as a pure function, with no
/// dependency on any plugin, so it's directly unit-testable regardless
/// of whether Firebase itself is configured in this environment (see
/// docs/PUSH_NOTIFICATIONS.md).
String? chatIdFromNotificationData(Map<String, dynamic> data) {
  if (data['type'] != 'message') return null;
  return data['chatId'] as String?;
}

/// Wraps Firebase Cloud Messaging (receiving pushes) and
/// flutter_local_notifications (displaying one while the app is in the
/// foreground — FCM only auto-shows a system notification when the app
/// isn't running in front of the user).
///
/// Every method here degrades to doing nothing — never throwing — when
/// this device has no working Firebase configuration (no real
/// `google-services.json`; see docs/PUSH_NOTIFICATIONS.md). The rest of
/// the app must never depend on push notifications actually working:
/// [SessionController] calls into this the same way whether or not a
/// Firebase project has been set up, and simply gets `null`/no-ops back
/// until one has.
class PushNotificationService {
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _chatIdToOpenController = StreamController<String>.broadcast();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  bool _initialized = false;

  /// True once a Firebase app has actually been initialized (i.e.
  /// `Firebase.initializeApp()` in main.dart succeeded, which itself
  /// requires a real `google-services.json` to be present) — every other
  /// method on this class checks this before touching `firebase_messaging`
  /// at all.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  /// Fires with a chatId every time a notification — the real system one
  /// (tapped while the app was backgrounded/killed) or the local one
  /// this class shows for a foreground message — is tapped and should
  /// open that chat. See `MessengerApp` for the listener that turns this
  /// into actual navigation.
  Stream<String> get chatIdToOpen => _chatIdToOpenController.stream;

  /// Test-only hook to simulate a notification tap — real ones only ever
  /// originate from `firebase_messaging`/`flutter_local_notifications`
  /// callbacks, neither of which resolves against a real plugin in a
  /// widget test (same boundary as `image_picker`/`record` elsewhere in
  /// this app). Lets tests prove the "tap -> navigate to the right chat"
  /// wiring end-to-end without one.
  @visibleForTesting
  void debugEmitChatIdToOpen(String chatId) =>
      _chatIdToOpenController.add(chatId);

  /// Sets up foreground/tapped-notification handling. Safe to call
  /// unconditionally at app startup regardless of whether Firebase is
  /// configured — a no-op in that case. Idempotent.
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

    // A push that arrives while the app is already open and in the
    // foreground doesn't get FCM's automatic system-tray notification —
    // that's an Android/iOS platform behavior, not something this app
    // controls — so it's shown explicitly here instead.
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    // Tapped while the app was backgrounded (not killed).
    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
    // Tapped while the app was fully killed — the tap is what launches
    // it, so this has to be polled once at startup rather than streamed.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleOpenedMessage(initialMessage);
  }

  /// Requests notification permission (the real OS prompt — Android 13+
  /// / iOS both gate this) and, if granted, returns this device's
  /// current FCM token. Null means either the user denied permission, or
  /// Firebase isn't configured at all — [SessionController] treats both
  /// the same way (nothing to register), which is the correct behavior
  /// for "Notifications OFF" either way it happens.
  Future<String?> requestPermissionAndGetToken() async {
    if (!isAvailable) return null;
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    return FirebaseMessaging.instance.getToken();
  }

  /// The current token without (re-)requesting permission — used by the
  /// "turn notifications off" path, which needs to know what token to
  /// unregister, not to prompt for anything.
  Future<String?> getCurrentToken() async {
    if (!isAvailable) return null;
    return FirebaseMessaging.instance.getToken();
  }

  /// Fires whenever Firebase rotates this device's token (happens
  /// occasionally, outside this app's control) — [SessionController]
  /// re-registers the new one so push delivery doesn't silently stop.
  /// An empty stream (never fires) when Firebase isn't configured.
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
