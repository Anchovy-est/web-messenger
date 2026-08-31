import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/typing_update.dart';
import '../../../providers/core_providers.dart';

/// Which other participant(s) in a chat are currently typing — a set of
/// user ids, not just a bool, since a *group* chat can have more than
/// one person typing at once and a stop event from one of them must
/// never clear the indicator for the others still typing. For a 1:1
/// chat this only ever holds 0 or 1 ids, so it behaves exactly like the
/// bool this used to be. One instance per chat (keyed by chatId via
/// `.family`), separate from [ChatDetailController] so a typing flicker
/// never has to rebuild (or be rebuilt by) the message list.
///
/// A stop event removes just that one user from the set immediately; a
/// start event adds them and also arms a per-user 5-second safety-net
/// timer that removes them on its own, in case the matching stop event
/// never arrives (app crash, connection drop, etc. on their end).
class TypingIndicatorController extends StateNotifier<Set<String>> {
  TypingIndicatorController(this._ref, this._chatId) : super(const {}) {
    _subscription = _ref
        .read(socketServiceProvider)
        .typingStream
        .listen(_onUpdate);
  }

  final Ref _ref;
  final String _chatId;
  late final StreamSubscription<TypingUpdate> _subscription;
  final Map<String, Timer> _autoClearTimers = {};

  void _onUpdate(TypingUpdate update) {
    if (update.chatId != _chatId) return;
    _autoClearTimers.remove(update.userId)?.cancel();
    if (update.isTyping) {
      state = {...state, update.userId};
      _autoClearTimers[update.userId] = Timer(const Duration(seconds: 5), () {
        if (mounted) _remove(update.userId);
      });
    } else {
      _remove(update.userId);
    }
  }

  void _remove(String userId) {
    if (!state.contains(userId)) return;
    state = {...state}..remove(userId);
  }

  @override
  void dispose() {
    for (final timer in _autoClearTimers.values) {
      timer.cancel();
    }
    _subscription.cancel();
    super.dispose();
  }
}

final typingIndicatorProvider = StateNotifierProvider.autoDispose
    .family<TypingIndicatorController, Set<String>, String>((ref, chatId) {
      return TypingIndicatorController(ref, chatId);
    });
