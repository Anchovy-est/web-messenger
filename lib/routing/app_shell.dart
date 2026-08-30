import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/responsive/breakpoints.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/chats/presentation/chat_list_screen.dart';
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
/// of a stretched phone screen: chats get a list pane and an inline
/// detail pane side by side (see [_MessagingPane]), while every other
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
                ? _MessagingPane(state: state, detail: child)
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

/// The desktop master-detail chat view: a fixed-width chat-list pane
/// (built on the exact same [ChatListBody] the mobile [ChatListScreen]
/// uses) beside whatever the currently-matched route's detail pane is —
/// [detail] itself (already the real `ChatDetailScreen` `ShellRoute`
/// built for `/chats/:id`) when a chat is open, or a plain placeholder at
/// `/`. Selecting a chat here updates the URL via `context.go` rather
/// than pushing — there's no "back" to navigate to on desktop, since the
/// list stays on screen the whole time; see [ChatListBody]'s own doc
/// comment.
class _MessagingPane extends StatelessWidget {
  const _MessagingPane({required this.state, required this.detail});

  final GoRouterState state;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final selectedChatId = state.pathParameters['id'];
    final hasOpenChat = selectedChatId != null;

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
          Expanded(child: hasOpenChat ? detail : const _NoChatSelectedView()),
        ],
      ),
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
