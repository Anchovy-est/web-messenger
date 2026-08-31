import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_providers.dart';
import '../../auth/domain/session_state.dart';
import '../../auth/presentation/session_controller.dart';
import 'chat_providers.dart';

/// Keeps "delivered" honest for messages that arrive while the recipient
/// isn't looking at that chat — watched app-wide from `app.dart`, unlike
/// `ChatDetailController` which only exists while a chat screen is
/// mounted. A chat that's actually open is covered separately, by its
/// own read-marking on load.
final messageDeliveryAckProvider = Provider<void>((ref) {
  final status = ref.watch(sessionControllerProvider.select((s) => s.status));
  if (status != SessionStatus.authenticated) return;

  final repository = ref.watch(messageRepositoryProvider);
  final subscription = ref.watch(socketServiceProvider).messageStream.listen((
    message,
  ) {
    // Best-effort — a failed ack just lags until the next one.
    unawaited(repository.markDelivered(message.chatId).catchError((_) {}));
  });
  ref.onDispose(subscription.cancel);
});
