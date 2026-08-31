import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Just enough to render one open chat panel's header — not the full
/// `Chat` model, since a panel can open from a deep link where only the
/// id (and maybe a title/avatar) is known.
class OpenChatPanel extends Equatable {
  const OpenChatPanel({required this.id, this.title, this.avatarUrl});

  final String id;
  final String? title;
  final String? avatarUrl;

  @override
  List<Object?> get props => [id, title, avatarUrl];
}

/// Which chats are open as side-by-side panels on a large window — a
/// desktop-only concept, untouched on mobile. `.autoDispose` resets it
/// once nothing's watching (window narrows, or logout), so a new
/// session never inherits a previous one's open chats.
class OpenChatPanelsController extends StateNotifier<List<OpenChatPanel>> {
  OpenChatPanelsController() : super(const []);

  /// Opens [panel] as a new rightmost panel — a no-op (not a duplicate
  /// or reorder) if already open. Also refreshes an open panel's
  /// title/avatar in place without disturbing its position.
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
