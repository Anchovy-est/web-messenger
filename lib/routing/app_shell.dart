import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/responsive/breakpoints.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/chats/presentation/chat_detail_screen.dart';
import '../features/chats/presentation/chat_list_screen.dart';
import '../features/chats/presentation/open_chat_panels_controller.dart';
import '../features/invitations/presentation/invitations_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../widgets/desktop_dialog.dart';
import '../widgets/user_avatar.dart';

/// Wraps every authenticated route (see `app_router.dart`'s `ShellRoute`).
///
/// On a [ScreenClass.compact] window this renders [child] completely
/// unchanged — every existing mobile screen (`ChatListScreen`,
/// `ChatDetailScreen`, `SearchScreen`, …) keeps its own full-screen
/// `Scaffold`/`AppBar`/back-button behavior exactly as it did before this
/// shell existed. Phones never see any of the rest of this file.
///
/// On a wider window this adds the persistent sidebar + master-detail
/// chrome that makes the app feel like a real desktop messenger instead
/// of a stretched phone screen: chats get a list pane beside one or more
/// simultaneously open chat panels (see [_MessagingPane] and
/// [openChatPanelsProvider]) — clicking a chat opens it alongside
/// whichever others are already open, rather than replacing them, so two
/// (or more) conversations can be read and replied to side by side; each
/// panel closes independently via its own close button. Every other
/// destination (Search, Invitations, Profile) is reached from the
/// sidebar — Search/Invitations as a quick desktop dialog (see
/// `showDesktopDialog`), Profile (and Edit profile, reached from within
/// it) as ordinary routed content next to the sidebar, width-capped so it
/// doesn't stretch edge-to-edge on a very wide monitor.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      sessionControllerProvider.select((s) => s.isAuthenticated),
    );
    // '/' briefly renders the splash screen (not `ChatListScreen`) while
    // a persisted session is still being restored — no sidebar to show
    // yet at that point, regardless of window width.
    if (context.isCompact || !isAuthenticated) return child;

    final location = state.matchedLocation;
    final isMessagingRoute = location == '/' || location.startsWith('/chats/');

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(location: location),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: isMessagingRoute
                ? _MessagingPane(state: state)
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: child,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});

  final String location;

  int get _selectedIndex {
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/invitations')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0; // '/' and every '/chats/*' both read as "Chats".
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final extended = context.isExpanded;

    return NavigationRail(
      extended: extended,
      minExtendedWidth: 216,
      selectedIndex: _selectedIndex,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.selected,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: UserAvatar(avatarUrl: user?.avatarUrl, radius: 20),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: () =>
                  ref.read(sessionControllerProvider.notifier).logout(),
            ),
          ),
        ),
      ),
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/');
          case 1:
            showDesktopDialog(context, child: const SearchScreen());
          case 2:
            showDesktopDialog(context, child: const InvitationsScreen());
          case 3:
            context.go('/profile');
        }
      },
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: Text('Chats'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.search),
          label: Text('Search'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.mail_outline),
          selectedIcon: Icon(Icons.mail),
          label: Text('Invitations'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profile'),
        ),
      ],
    );
  }
}

/// Every simultaneously open chat panel is given this much width; once
/// there isn't room for all of them at once, the panel row scrolls
/// horizontally instead of squeezing any one panel narrower than this —
/// see [_MessagingPane]'s `LayoutBuilder`.
const _minPanelWidth = 380.0;

/// The desktop chat view: a fixed-width chat-list pane (built on the
/// exact same [ChatListBody] the mobile [ChatListScreen] uses) beside
/// one [ChatDetailScreen] per entry in [openChatPanelsProvider] — this
/// is what lets two or more conversations be open, visible, and
/// independently usable on the same page at once (each is its own
/// `ChatDetailScreen`/`ChatDetailController` instance, so each keeps
/// receiving and sending on its own regardless of what the others are
/// doing). Selecting a chat in the list updates the URL via
/// `context.go` — [_MessagingPaneState.didUpdateWidget] is what turns
/// that into "make sure this chat has an open panel" and scrolls it
/// into view, so a plain chat-tile tap is all a caller ever needs to do;
/// nothing here needs to be told separately to "open a panel". A panel
/// closes independently via the close button [ChatDetailScreen] shows
/// when given `onClose` — closing the one the URL currently points at
/// also navigates back to `/`, so the two don't fight (see
/// [_MessagingPaneState._closePanel]).
///
/// When there's room, every open panel gets an equal share of the
/// available width, matching this phase's mockup; once there are more
/// panels than comfortably fit, the row scrolls horizontally instead so
/// no panel ever gets squeezed below [_minPanelWidth].
class _MessagingPane extends ConsumerStatefulWidget {
  const _MessagingPane({required this.state});

  final GoRouterState state;

  @override
  ConsumerState<_MessagingPane> createState() => _MessagingPaneState();
}

class _MessagingPaneState extends ConsumerState<_MessagingPane> {
  final _panelsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromRoute());
  }

  @override
  void didUpdateWidget(covariant _MessagingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.pathParameters['id'] !=
        oldWidget.state.pathParameters['id']) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromRoute());
    }
  }

  @override
  void dispose() {
    _panelsScrollController.dispose();
    super.dispose();
  }

  /// Makes sure the URL's current chat (if any) has an open panel —
  /// covers both a chat-list tap (which just calls `context.go`, same as
  /// it always has) and landing straight on `/chats/:id` from a fresh
  /// deep link — then scrolls that panel into view. Deliberately never
  /// *closes* panels the URL doesn't mention: navigating to `/` (e.g.
  /// the sidebar's "Chats" destination) or to some other still-open
  /// chat must not silently discard every other panel the user has open.
  void _syncFromRoute() {
    if (!mounted) return;
    final chatId = widget.state.pathParameters['id'];
    if (chatId == null) return;
    final extra = widget.state.extra as Map<String, dynamic>?;
    ref
        .read(openChatPanelsProvider.notifier)
        .open(
          OpenChatPanel(
            id: chatId,
            title: extra?['title'] as String?,
            avatarUrl: extra?['avatarUrl'] as String?,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPanel(chatId));
  }

  void _scrollToPanel(String chatId) {
    if (!mounted || !_panelsScrollController.hasClients) return;
    final panels = ref.read(openChatPanelsProvider);
    final index = panels.indexWhere((p) => p.id == chatId);
    if (index == -1) return;
    final target = index * (_minPanelWidth + 1); // +1 for each divider
    _panelsScrollController.animateTo(
      target.clamp(0, _panelsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _closePanel(String chatId) {
    ref.read(openChatPanelsProvider.notifier).close(chatId);
    // The URL was pointing at exactly the panel that just closed — move
    // it back to `/` so a chat-list tap on the same chat (or a page
    // reload) doesn't just re-open the panel this close button was
    // supposed to get rid of.
    if (widget.state.pathParameters['id'] == chatId) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final panels = ref.watch(openChatPanelsProvider);
    final selectedChatId = widget.state.pathParameters['id'];

    return DefaultTabController(
      length: 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 360,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chats',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                const TabBar(tabs: chatListTabs),
                Expanded(
                  child: ChatListBody(
                    selectedChatId: selectedChatId,
                    onChatSelected: (chat) => context.go(
                      '/chats/${chat.id}',
                      extra: chatRouteExtra(chat),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: panels.isEmpty
                ? const _NoChatSelectedView()
                : _PanelRow(
                    panels: panels,
                    scrollController: _panelsScrollController,
                    onClose: _closePanel,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Lays out every open panel, sized either as an equal `Expanded` share
/// (when they all fit at [_minPanelWidth] or wider) or as a fixed-width,
/// horizontally scrolling row (once they wouldn't) — recomputed on every
/// build via `LayoutBuilder`, so resizing the window across that
/// threshold, or opening/closing a panel, always re-settles into
/// whichever layout actually fits.
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.panels,
    required this.scrollController,
    required this.onClose,
  });

  final List<OpenChatPanel> panels;
  final ScrollController scrollController;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsWithoutScrolling =
            panels.length * _minPanelWidth <= constraints.maxWidth;

        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, panel) in panels.indexed) ...[
              fitsWithoutScrolling
                  ? Expanded(child: _panelFor(panel))
                  : SizedBox(width: _minPanelWidth, child: _panelFor(panel)),
              if (index < panels.length - 1)
                const VerticalDivider(width: 1, thickness: 1),
            ],
          ],
        );

        if (fitsWithoutScrolling) return row;
        return Scrollbar(
          controller: scrollController,
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: row,
          ),
        );
      },
    );
  }

  // Keyed by chat id — without this, closing a panel in the middle of
  // the row would shift every panel after it into a new list index, and
  // Flutter would happily reuse each `ChatDetailScreen`'s *State* (its
  // scroll position, its search box, its in-progress recording, …)
  // across what is, as far as the user's concerned, a completely
  // different chat.
  Widget _panelFor(OpenChatPanel panel) {
    return ChatDetailScreen(
      key: ValueKey(panel.id),
      chatId: panel.id,
      title: panel.title,
      avatarUrl: panel.avatarUrl,
      onClose: () => onClose(panel.id),
    );
  }
}

class _NoChatSelectedView extends StatelessWidget {
  const _NoChatSelectedView();

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 72, color: outline),
          const SizedBox(height: 16),
          Text(
            'Select a chat to start messaging',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: outline),
          ),
        ],
      ),
    );
  }
}
