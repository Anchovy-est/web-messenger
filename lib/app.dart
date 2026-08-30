import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/chats/data/message_delivery_ack_provider.dart';
import 'providers/core_providers.dart';
import 'routing/app_router.dart';
import 'widgets/floral_background.dart';

class MessengerApp extends ConsumerStatefulWidget {
  const MessengerApp({super.key});

  @override
  ConsumerState<MessengerApp> createState() => _MessengerAppState();
}

class _MessengerAppState extends ConsumerState<MessengerApp> {
  StreamSubscription<String>? _chatIdToOpenSubscription;

  @override
  void initState() {
    super.initState();
    final pushService = ref.read(pushNotificationServiceProvider);
    // Subscribed *before* calling initialize() below — chatIdToOpen is a
    // broadcast stream with no replay, so a tap-that-launched-the-app
    // event (getInitialMessage, inside initialize()) would be silently
    // dropped if this listener attached even one microtask later.
    _chatIdToOpenSubscription = pushService.chatIdToOpen.listen(_openChat);
    unawaited(pushService.initialize());
  }

  void _openChat(String chatId) {
    // Reads the router fresh on every call (not cached) since
    // appRouterProvider rebuilds — a whole new GoRouter instance — on
    // every session status transition (see its own doc comment); a
    // stale reference here could push onto a router that's no longer
    // the one actually mounted.
    ref.read(appRouterProvider).push('/chats/$chatId');
  }

  @override
  void dispose() {
    _chatIdToOpenSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    // Side-effect-only provider — keeps "delivered" current for every
    // chat, not just whichever one's screen happens to be open.
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
      // A single explicit theme, not `theme`/`darkTheme`/`ThemeMode.system`
      // — [ThemeController] is the one place OS brightness is consulted
      // (only as the *default*, before any explicit choice exists; see
      // its own doc comment), so `MaterialApp` itself never needs to pick
      // between two themes on its own.
      theme: themeData,
      themeMode: ThemeMode.light,
      routerConfig: router,
      // Wraps every screen's (now-transparent, in Floral — see
      // `AppTheme.floral`) Scaffold in the decorative flower backdrop —
      // one wrap point here, not something every screen has to opt into
      // individually. Any other theme renders `child` completely
      // unwrapped: no flowers, no trace of Floral, exactly as if this
      // widget didn't exist.
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (themeOption != AppThemeOption.floral) return content;
        return FloralBackground(child: content);
      },
    );
  }
}
