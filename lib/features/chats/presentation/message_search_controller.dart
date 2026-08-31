import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/message.dart';
import 'chat_detail_controller.dart';

/// Search *within* one already-open chat's thread — text messages the
/// device has already decrypted (see the class doc comment on
/// [MessageSearchController] for why this can only ever be client-side).
/// Distinct from `SearchController`/`SearchScreen`, which searches for
/// *people* to invite, not message content.
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

  /// Index into [matches] the user last navigated to (via
  /// [MessageSearchController.next]/[previous], or landed on when a new
  /// search started) — `-1` means no query, or a query with no matches.
  final int selectedIndex;

  bool get isActive => query.isNotEmpty;
  int get totalMatches => matches.length;

  String? get selectedMessageId =>
      (selectedIndex >= 0 && selectedIndex < matches.length)
      ? matches[selectedIndex]
      : null;
}

/// Finds text messages in one chat's already-decrypted thread that
/// contain the current search query — and *only* that. This has to be
/// entirely client-side: message bodies are end-to-end encrypted (see
/// `EncryptionService`), so the server never has plaintext to search in
/// the first place, and building any kind of server-side search index
/// would mean either storing a plaintext (or plaintext-derived, e.g.
/// stemmed/tokenized) index the server could read — defeating the whole
/// point of end-to-end encryption — or a much more involved searchable-
/// encryption scheme that's real cryptography research, not a
/// reasonable scope for this feature. Searching the plaintext this
/// device already holds in memory, having already decrypted it to
/// display the thread in the first place, costs nothing extra and
/// leaks nothing new.
///
/// One instance per chat (keyed by chatId via `.family`), watching
/// [chatDetailControllerProvider] so a new message arriving mid-search
/// (or a message being edited/deleted) re-filters automatically.
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

    // A message arriving/changing mid-search shouldn't yank the view
    // away from whatever match the user was already looking at, as long
    // as it's still a match; otherwise land on the most recent one —
    // the messages nearest the bottom of the thread, which is what's
    // already on screen most of the time.
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
