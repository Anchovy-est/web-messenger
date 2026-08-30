import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import '../../../models/chat.dart';
import '../../../widgets/connection_banner.dart';
import '../../../widgets/empty_state_view.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/user_avatar.dart';
import '../../auth/presentation/session_controller.dart';
import 'chat_list_controller.dart';

/// The `extra` map every chat-tile tap hands to the `/chats/:id` route —
/// pulled out so the mobile push (below) and the desktop shell's inline
/// selection (see `AppShell`) build it identically from the same [Chat]
/// instead of each re-deriving it.
Map<String, dynamic> chatRouteExtra(Chat chat) => {
  'title': chat.displayName('Unknown'),
  'avatarUrl': chat.otherParticipant?.avatarUrl,
};

/// The app's real landing screen once signed in — the chat list. This is
/// the full-screen phone experience: its own [AppBar] with the
/// search/invitations/profile/logout actions, tapping a chat pushes
/// [ChatDetailScreen] as a new full-screen route. On a wide (desktop/web)
/// window, `AppShell` doesn't render this screen at all — it composes
/// [ChatListBody] directly, side-by-side with the open chat, instead —
/// so nothing here needs to know or care that a wider layout exists.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mobile Messenger'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: () => context.push('/search'),
            ),
            IconButton(
              icon: const Icon(Icons.mail_outline),
              tooltip: 'Invitations',
              onPressed: () => context.push('/invitations'),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Profile',
              onPressed: () => context.push('/profile'),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: () =>
                  ref.read(sessionControllerProvider.notifier).logout(),
            ),
          ],
          bottom: const TabBar(tabs: chatListTabs),
        ),
        body: Column(
          children: [
            const ConnectionBanner(),
            if (user != null && !user.emailVerified)
              MaterialBanner(
                content: const Text(
                  'Verify your email to secure your account.',
                ),
                leading: const Icon(Icons.mark_email_unread_outlined),
                actions: [
                  TextButton(
                    onPressed: () => context.push('/verify-email'),
                    child: const Text('Verify'),
                  ),
                ],
              ),
            Expanded(
              child: ChatListBody(
                onChatSelected: (chat) => context.push(
                  '/chats/${chat.id}',
                  extra: chatRouteExtra(chat),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `Tab`s shared by [ChatListScreen]'s `AppBar.bottom` (mobile) and
/// `AppShell`'s own plain `TabBar` above [ChatListBody] on desktop — same
/// two tabs either way, just mounted in a different chrome.
const chatListTabs = [Tab(text: 'Chats'), Tab(text: 'Archived')];

/// The Active/Archived tabbed list of chats — every bit of this screen
/// that isn't chrome (app bar, connection/verification banners), and so
/// the one piece [ChatListScreen] (mobile, full screen) and the desktop
/// shell's chat-list pane (see `AppShell`) both build on, instead of the
/// list-rendering/archive logic existing twice. Must be used inside a
/// `DefaultTabController(length: 2)` ancestor — neither of this widget's
/// two call sites builds a `TabBarView` without also providing one.
class ChatListBody extends StatelessWidget {
  const ChatListBody({
    super.key,
    required this.onChatSelected,
    this.selectedChatId,
  });

  /// Called with the tapped [Chat] — mobile pushes `/chats/:id` as a new
  /// full-screen route; the desktop shell instead just updates which chat
  /// is shown in its already-visible detail pane (see `AppShell`).
  final ValueChanged<Chat> onChatSelected;

  /// The chat currently open in an adjacent detail pane, if any —
  /// highlighted in the list so it's clear which conversation is showing.
  /// Always `null` on mobile, where the list and the open chat are never
  /// both on screen at once.
  final String? selectedChatId;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: [
        _ActiveTab(
          onChatSelected: onChatSelected,
          selectedChatId: selectedChatId,
        ),
        _ArchivedTab(
          onChatSelected: onChatSelected,
          selectedChatId: selectedChatId,
        ),
      ],
    );
  }
}

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab({required this.onChatSelected, this.selectedChatId});

  final ValueChanged<Chat> onChatSelected;
  final String? selectedChatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeChatsControllerProvider);

    return state.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorStateView(
        message: error is ApiException
            ? error.message
            : 'Something went wrong.',
        onRetry: () =>
            ref.read(activeChatsControllerProvider.notifier).refresh(),
      ),
      data: (chats) {
        // Always wrapped in a RefreshIndicator, empty or not — a
        // just-accepted invitation can leave a viewer stuck looking at
        // an empty list with no visible action but a full app restart
        // otherwise, since pull-to-refresh is the only refresh affordance
        // this screen has (see _wrapRefreshable doc comment).
        return _wrapRefreshable(
          onRefresh: () =>
              ref.read(activeChatsControllerProvider.notifier).refresh(),
          child: chats.isEmpty
              ? const EmptyStateView(
                  text:
                      'No chats yet.\nSearch for someone and send an invitation to start one.',
                )
              : ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return _ChatTile(
                      chat: chat,
                      selected: chat.id == selectedChatId,
                      onTap: () => onChatSelected(chat),
                      trailing: IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'Archive',
                        onPressed: () => ref
                            .read(activeChatsControllerProvider.notifier)
                            .archive(chat.id),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _ArchivedTab extends ConsumerWidget {
  const _ArchivedTab({required this.onChatSelected, this.selectedChatId});

  final ValueChanged<Chat> onChatSelected;
  final String? selectedChatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(archivedChatsControllerProvider);

    return state.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorStateView(
        message: error is ApiException
            ? error.message
            : 'Something went wrong.',
        onRetry: () =>
            ref.read(archivedChatsControllerProvider.notifier).refresh(),
      ),
      data: (chats) {
        return _wrapRefreshable(
          onRefresh: () =>
              ref.read(archivedChatsControllerProvider.notifier).refresh(),
          child: chats.isEmpty
              ? const EmptyStateView(text: 'No archived chats.')
              : ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return _ChatTile(
                      chat: chat,
                      selected: chat.id == selectedChatId,
                      onTap: () => onChatSelected(chat),
                      trailing: IconButton(
                        icon: const Icon(Icons.unarchive_outlined),
                        tooltip: 'Unarchive',
                        onPressed: () => ref
                            .read(archivedChatsControllerProvider.notifier)
                            .unarchive(chat.id),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// A `RefreshIndicator` needs a scrollable descendant to detect the pull
/// gesture at all — `ListView.builder` already qualifies once there are
/// items, but `EmptyStateView` (a bare `Center`) doesn't, which is
/// exactly the gap that used to leave a viewer with an empty chat list
/// and no way to pull-to-refresh it (e.g. right after accepting an
/// invitation, before the new chat has loaded in) short of restarting
/// the app. Wrapping every child — empty-state included — in a
/// single-child `ListView` with `AlwaysScrollableScrollPhysics` gives it
/// that scrollable, so the gesture works regardless of which child is
/// showing.
Widget _wrapRefreshable({
  required Future<void> Function() onRefresh,
  required Widget child,
}) {
  return RefreshIndicator(
    onRefresh: onRefresh,
    child: child is ListView
        ? child
        : ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [child],
          ),
  );
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.trailing,
    required this.onTap,
    this.selected = false,
  });

  final Chat chat;
  final Widget trailing;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final title = chat.displayName('Unknown');
    final lastMessage = chat.lastMessage;

    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      leading: UserAvatar(
        avatarUrl: chat.otherParticipant?.avatarUrl,
        radius: 24,
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          if (chat.isMuted) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.notifications_off,
              size: 14,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ],
      ),
      subtitle: Text(
        lastMessage == null
            ? 'No messages yet.'
            : (lastMessage.body ?? 'Attachment'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
