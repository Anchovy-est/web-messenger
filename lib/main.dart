import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'widgets/app_error_fallback.dart';

/// Required by FCM for a push that arrives while the app is killed —
/// the system tray notification and tap handling are covered elsewhere,
/// this just satisfies the registration requirement.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // No Firebase project configured — nothing to do.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A widget that throws while building shows this calm fallback
  // instead of Flutter's own error screen; everything else keeps
  // working. `PlatformDispatcher.onError` catches whatever else slips
  // through uncaught.
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
    // No Firebase project configured — the app runs normally either way.
  }
  runApp(const ProviderScope(child: MessengerApp()));
}
