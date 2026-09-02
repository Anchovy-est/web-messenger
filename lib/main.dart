import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'widgets/app_error_fallback.dart';

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

  runApp(const ProviderScope(child: MessengerApp()));
}
