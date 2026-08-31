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

/// The `extra` map every chat-tile tap hands to the `/chats/:id` route.
Map<String, dynamic> chatRouteExtra(Chat chat) => {
  'title': chat.displayName('Unknown'),
  'avatarUrl': chat.otherParticipant?.avatarUrl,
};

/// The full-screen phone landing screen once signed in. On a wide
/// window, `AppShell` composes [ChatListBody] directly instead.
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

/// Shared by [ChatListScreen]'s mobile `AppBar.bottom` and `AppShell`'s
/// desktop `TabBar`.
const chatListTabs = [Tab(text: 'Chats'), Tab(text: 'Archived')];

/// The Active/Archived tabbed list of chats — the part [ChatListScreen]
/// and the desktop shell both build on. Needs a
/// `DefaultTabController(length: 2)` ancestor.
class ChatListBody extends StatelessWidget {
  const ChatListBody({
    super.key,
    required this.onChatSelected,
    this.selectedChatId,
  });

  /// Called with the tapped [Chat] — mobile pushes a route; desktop
  /// updates its already-visible detail pane.
  final ValueChanged<Chat> onChatSelected;

  /// The chat currently open in an adjacent detail pane, for
  /// highlighting. Always null on mobile.
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
        message: errorMessageFor(error),
        onRetry: () =>
            ref.read(activeChatsControllerProvider.notifier).refresh(),
      ),
      data: (chats) {
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
        message: errorMessageFor(error),
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

/// `RefreshIndicator` needs a scrollable descendant — `EmptyStateView`
/// (a bare `Center`) doesn't qualify on its own, so pull-to-refresh
/// would silently stop working on an empty list. Wrapping every child in
/// a single-child scrollable `ListView` fixes that regardless of which
/// child is showing.
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
        placeholderIcon: chat.isGroup ? Icons.groups : Icons.person,
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
