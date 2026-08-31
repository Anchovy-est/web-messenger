import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Just enough to render one open chat panel's header (see `AppShell`'s
/// `_MessagingPane`) — deliberately not the full `Chat` model: a panel
/// can be opened from a deep link (`/chats/:id`, on a fresh page load)
/// where all that's known is the id and whatever `title`/`avatarUrl`
/// happened to ride along as the route's `extra` (possibly nothing, on a
/// hard browser refresh — go_router doesn't persist `extra` across one).
/// `ChatDetailScreen` already falls back to a plain "Chat" title in that
/// case, same as it always has.
class OpenChatPanel extends Equatable {
  const OpenChatPanel({required this.id, this.title, this.avatarUrl});

  final String id;
  final String? title;
  final String? avatarUrl;

  @override
  List<Object?> get props => [id, title, avatarUrl];
}

/// Which chats are open as side-by-side panels on a large (desktop/web)
/// window — see `AppShell`'s `_MessagingPane`. Purely a desktop-window
/// concept: on a compact window, `AppShell` never even builds the
/// widgets that read this, so it stays untouched and mobile navigation
/// is exactly what it always was (see `AppShell`'s own class doc
/// comment).
///
/// `.autoDispose` so this resets itself the moment nothing's watching it
/// any more — in particular, when `AppShell` stops rendering the desktop
/// chrome at all (window narrows to compact, or the user logs out and
/// `isAuthenticated` goes false) — rather than quietly carrying a
/// previous session's open chats into a new one, mirroring every other
/// per-session controller in this feature
/// (`activeChatsControllerProvider`, `chatMuteControllerProvider`, …).
class OpenChatPanelsController extends StateNotifier<List<OpenChatPanel>> {
  OpenChatPanelsController() : super(const []);

  /// Opens [panel] as a new rightmost panel — a no-op if that chat is
  /// already open (never a duplicate, and never reordered just because
  /// it was tapped again). Also used to *refresh* an already-open
  /// panel's title/avatar in place should a fresher one come along (e.g.
  /// the chat list resolves a display name the initial deep link didn't
  /// have), without disturbing its position or, critically, its
  /// [ChatDetailScreen]'s own widget identity/state (see the `ValueKey`
  /// each panel is built with in `_MessagingPane`).
  void open(OpenChatPanel panel) {
    final index = state.indexWhere((p) => p.id == panel.id);
    if (index == -1) {
      state = [...state, panel];
      return;
    }
    if (state[index] == panel) return; // already exactly this
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) panel else state[i],
    ];
  }

  void close(String chatId) {
    state = [
      for (final panel in state)
        if (panel.id != chatId) panel,
    ];
  }
}

final openChatPanelsProvider =
    StateNotifierProvider.autoDispose<
      OpenChatPanelsController,
      List<OpenChatPanel>
    >((ref) => OpenChatPanelsController());
