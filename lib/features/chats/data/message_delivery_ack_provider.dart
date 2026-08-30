import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_providers.dart';
import '../../auth/domain/session_state.dart';
import '../../auth/presentation/session_controller.dart';
import 'chat_providers.dart';

/// Keeps "delivered" honest for messages that arrive while the recipient
/// isn't looking at that specific chat's thread — e.g. sitting on the
/// chat list, or with a different chat open. Watched once, for the whole
/// app's lifetime, from `app.dart`; unlike `ChatDetailController` (which
/// only exists per-chat while that screen is mounted), this listens to
/// *every* incoming message regardless of which screen is showing.
///
/// Delivery for a chat that's actually open is also covered separately —
/// `ChatDetailController.refresh()` marks read (which implies delivered)
/// the moment its history load succeeds — so this provider's job is
/// specifically the "message arrived somewhere I'm not looking" case.
final messageDeliveryAckProvider = Provider<void>((ref) {
  final status = ref.watch(sessionControllerProvider.select((s) => s.status));
  if (status != SessionStatus.authenticated) return;

  final repository = ref.watch(messageRepositoryProvider);
  final subscription = ref.watch(socketServiceProvider).messageStream.listen((
    message,
  ) {
    // Best-effort: a failed ack just means "delivered" lags behind
    // until the next successful one (e.g. the recipient opening the
    // chat, which also marks it) — not worth surfacing to the user.
    unawaited(repository.markDelivered(message.chatId).catchError((_) {}));
  });
  ref.onDispose(subscription.cancel);
});
