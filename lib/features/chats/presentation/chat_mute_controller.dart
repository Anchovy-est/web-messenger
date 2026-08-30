import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_providers.dart';
import '../data/chat_repository.dart';

/// Whether the current user has muted this chat's push notifications —
/// one instance per chat (keyed by chatId via `.family`), separate from
/// [ChatDetailController] for the same reason [TypingIndicatorController]
/// is: this is its own small, independent concern, not something the
/// message-thread controller needs to carry around.
///
/// Fetches the chat once, on creation, purely to read its current
/// [Chat.mutedAt] — [ChatDetailScreen] doesn't otherwise have that value
/// on hand (it navigates in with only a chat id/title/avatar, not a full
/// [Chat]). [toggle] is optimistic-free by design: it waits for the
/// server's confirmation before flipping the icon, since a push-setting
/// toggle is rare enough that the round trip is imperceptible, and
/// getting it visibly wrong (showing "muted" when the request actually
/// failed) is worse than a few hundred milliseconds of a disabled button.
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

  /// Mutes if currently unmuted, unmutes if currently muted. A no-op
  /// (not an error) while the initial load is still in flight or already
  /// failed — there's nothing known to toggle yet in either case.
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
      // Two separate assignments, deliberately — see
      // NotificationSettingsController.setEnabled's identical pattern
      // for why collapsing this into one would silently lose the error
      // state before anything could ever observe it. Settling back to
      // [previous] is "last stable state" rather than getting stuck on
      // the loading spinner or landing on a value that was never
      // confirmed.
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
