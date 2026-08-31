import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/typing_update.dart';
import '../../../providers/core_providers.dart';

/// Which other participants in a chat are currently typing — a set of
/// user ids, since a group chat can have more than one at once. A stop
/// event removes that user immediately; a start event also arms a
/// 5-second safety-net timer in case the stop never arrives.
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
