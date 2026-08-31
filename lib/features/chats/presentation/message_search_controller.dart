import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/message.dart';
import 'chat_detail_controller.dart';

/// Search within one already-open chat's thread. Distinct from
/// `SearchController`, which searches for people to invite, not
/// message content.
class MessageSearchState {
  const MessageSearchState({
    this.query = '',
    this.matches = const [],
    this.selectedIndex = -1,
  });

  final String query;

  /// Every text message's id whose plaintext body contains [query]
  /// (case-insensitively), in the same oldest-first order the thread
  /// itself renders in.
  final List<String> matches;

  /// Index into [matches] the user last navigated to — `-1` means no
  /// query, or no matches.
  final int selectedIndex;

  bool get isActive => query.isNotEmpty;
  int get totalMatches => matches.length;

  String? get selectedMessageId =>
      (selectedIndex >= 0 && selectedIndex < matches.length)
      ? matches[selectedIndex]
      : null;
}

/// Finds text messages in one chat's already-decrypted thread matching
/// the search query. Entirely client-side — message bodies are
/// end-to-end encrypted, so the server never has plaintext to index or
/// search. Watches the chat's own message list, so new/edited/deleted
/// messages re-filter automatically.
class MessageSearchController extends StateNotifier<MessageSearchState> {
  MessageSearchController(this._ref, this._chatId)
    : super(const MessageSearchState()) {
    _subscription = _ref.listen(
      chatDetailControllerProvider(_chatId),
      (previous, next) => _recompute(state.query),
    );
  }

  final Ref _ref;
  final String _chatId;
  late final ProviderSubscription<AsyncValue<List<Message>>> _subscription;

  void updateQuery(String query) => _recompute(query);

  void _recompute(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const MessageSearchState();
      return;
    }

    final messages =
        _ref.read(chatDetailControllerProvider(_chatId)).valueOrNull ??
        const [];
    final lowerQuery = trimmed.toLowerCase();
    final matches = [
      for (final message in messages)
        if (!message.isDeleted &&
            message.type == 'text' &&
            (message.body?.toLowerCase().contains(lowerQuery) ?? false))
          message.id,
    ];

    // Keep the current match selected if it's still a match; otherwise
    // land on the most recent one.
    final previousId = state.selectedMessageId;
    final newIndex = (previousId != null && matches.contains(previousId))
        ? matches.indexOf(previousId)
        : (matches.isEmpty ? -1 : matches.length - 1);

    state = MessageSearchState(
      query: query,
      matches: matches,
      selectedIndex: newIndex,
    );
  }

  void next() {
    if (state.matches.isEmpty) return;
    state = MessageSearchState(
      query: state.query,
      matches: state.matches,
      selectedIndex: (state.selectedIndex + 1) % state.matches.length,
    );
  }

  void previous() {
    if (state.matches.isEmpty) return;
    state = MessageSearchState(
      query: state.query,
      matches: state.matches,
      selectedIndex:
          (state.selectedIndex - 1 + state.matches.length) %
          state.matches.length,
    );
  }

  void clear() => state = const MessageSearchState();

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

final messageSearchControllerProvider = StateNotifierProvider.autoDispose
    .family<MessageSearchController, MessageSearchState, String>((ref, chatId) {
      return MessageSearchController(ref, chatId);
    });
