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

/// The app's real landing screen once signed in — the chat list.
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chats'),
              Tab(text: 'Archived'),
            ],
          ),
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
            const Expanded(
              child: TabBarView(children: [_ActiveTab(), _ArchivedTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab();

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
  const _ArchivedTab();

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
  const _ChatTile({required this.chat, required this.trailing});

  final Chat chat;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final title = chat.displayName('Unknown');
    final lastMessage = chat.lastMessage;

    return ListTile(
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
      onTap: () => context.push(
        '/chats/${chat.id}',
        extra: {'title': title, 'avatarUrl': chat.otherParticipant?.avatarUrl},
      ),
    );
  }
}
