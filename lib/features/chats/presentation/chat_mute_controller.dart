import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_providers.dart';
import '../data/chat_repository.dart';

/// Whether the current user has muted this chat's push notifications —
/// one instance per chat. Not optimistic: waits for the server before
/// flipping the icon, since getting it visibly wrong is worse than a
/// brief disabled button.
class ChatMuteController extends StateNotifier<AsyncValue<bool>> {
  ChatMuteController(this._chatId, this._repository)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final String _chatId;
  final ChatRepository _repository;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final chat = await _repository.getChat(_chatId);
      return chat.isMuted;
    });
    if (!mounted) return;
    state = result;
  }

  /// Mutes if unmuted, unmutes if muted. No-op while the initial load
  /// is still in flight.
  Future<void> toggle() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final previous = state;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      if (current) {
        await _repository.unmute(_chatId);
      } else {
        await _repository.mute(_chatId);
      }
      return !current;
    });
    if (!mounted) return;
    if (result.hasError) {
      // Let listeners see the error, then settle back to the last
      // stable value.
      state = result;
      if (!mounted) return;
      state = previous;
    } else {
      state = result;
    }
  }
}

final chatMuteControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatMuteController, AsyncValue<bool>, String>((ref, chatId) {
      return ChatMuteController(chatId, ref.watch(chatRepositoryProvider));
    });
