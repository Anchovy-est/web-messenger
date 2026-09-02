import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/chats/data/message_delivery_ack_provider.dart';
import 'routing/app_router.dart';
import 'widgets/floral_background.dart';

class MessengerApp extends ConsumerStatefulWidget {
  const MessengerApp({super.key});

  @override
  ConsumerState<MessengerApp> createState() => _MessengerAppState();
}

class _MessengerAppState extends ConsumerState<MessengerApp> {
  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    // Keeps "delivered" current for every chat, not just the open one.
    ref.watch(messageDeliveryAckProvider);

    final themeOption = ref.watch(themeControllerProvider);
    final themeData = switch (themeOption) {
      AppThemeOption.light => AppTheme.light(),
      AppThemeOption.dark => AppTheme.dark(),
      AppThemeOption.floral => AppTheme.floral(),
    };

    return MaterialApp.router(
      title: 'Mobile Messenger',
      debugShowCheckedModeBanner: false,
      // One explicit theme — ThemeController already picked it.
      theme: themeData,
      themeMode: ThemeMode.light,
      routerConfig: router,
      // Wraps every screen in the decorative flower backdrop, Floral
      // theme only.
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (themeOption != AppThemeOption.floral) return content;
        return FloralBackground(child: content);
      },
    );
  }
}
