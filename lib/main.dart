import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'widgets/app_error_fallback.dart';

/// FCM requires this to be a top-level (or static) function, run in its
/// own isolate, for a push that arrives while the app is fully killed or
/// backgrounded. There's nothing for it to actually do: FCM already
/// shows a system-tray notification automatically in that case (the
/// `notification` block on the payload — see
/// backend/src/services/push.service.js), and tapping it is handled by
/// `PushNotificationService.initialize`'s `getInitialMessage`/
/// `onMessageOpenedApp` wiring once the app itself launches. This
/// handler exists only because Firebase requires *something* to be
/// registered, not because this app needs background processing.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // No real Firebase project configured yet (see
    // docs/PUSH_NOTIFICATIONS.md) — nothing to do either way.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error resilience: a widget that throws while building/laying
  // out/painting shows this calm fallback instead of Flutter's own
  // error widget (blank in release builds, alarming in debug ones) —
  // Flutter already scopes the failure to just that one widget, so
  // everything else on screen keeps working. `PlatformDispatcher.onError`
  // catches whatever else reaches the platform layer uncaught (returning
  // true marks it handled, so it's logged instead of crashing the
  // isolate) — together these are what keeps the app in a recoverable
  // state after an unexpected error rather than dying outright, with the
  // error itself visible via [AppErrorFallback] instead of silent.
  ErrorWidget.builder = (details) {
    FlutterError.presentError(details);
    return const AppErrorFallback();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {
    // No real Firebase project configured yet — the rest of the app
    // runs exactly as it would otherwise; `PushNotificationService`
    // checks `Firebase.apps.isNotEmpty` before touching anything that
    // would need it. See docs/PUSH_NOTIFICATIONS.md for how to set one
    // up.
  }
  runApp(const ProviderScope(child: MessengerApp()));
}
