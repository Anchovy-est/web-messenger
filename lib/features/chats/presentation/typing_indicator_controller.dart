import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/typing_update.dart';
import '../../../providers/core_providers.dart';

/// Whether the other participant in a chat is currently typing (Phase
/// 15). One instance per chat (keyed by chatId via `.family`), separate
/// from [ChatDetailController] so a typing flicker never has to rebuild
/// (or be rebuilt by) the message list.
///
/// A stop event clears it immediately; a start event also arms a 5-second
/// safety-net timer that clears it on its own, in case the matching stop
/// event never arrives (app crash, connection drop, etc. on the other
/// end).
class TypingIndicatorController extends StateNotifier<bool> {
  TypingIndicatorController(this._ref, this._chatId) : super(false) {
    _subscription = _ref
        .read(socketServiceProvider)
        .typingStream
        .listen(_onUpdate);
  }

  final Ref _ref;
  final String _chatId;
  late final StreamSubscription<TypingUpdate> _subscription;
  Timer? _autoClearTimer;

  void _onUpdate(TypingUpdate update) {
    if (update.chatId != _chatId) return;
    _autoClearTimer?.cancel();
    if (update.isTyping) {
      state = true;
      _autoClearTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) state = false;
      });
    } else {
      state = false;
    }
  }

  @override
  void dispose() {
    _autoClearTimer?.cancel();
    _subscription.cancel();
    super.dispose();
  }
}

final typingIndicatorProvider = StateNotifierProvider.autoDispose
    .family<TypingIndicatorController, bool, String>((ref, chatId) {
      return TypingIndicatorController(ref, chatId);
    });
