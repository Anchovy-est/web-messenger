import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../models/invitation.dart';
import '../../../widgets/empty_state_view.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/user_avatar.dart';
import 'invitations_controller.dart';

class InvitationsScreen extends StatelessWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Invitations'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Received'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: const TabBarView(children: [_ReceivedTab(), _SentTab()]),
      ),
    );
  }
}

class _ReceivedTab extends ConsumerWidget {
  const _ReceivedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receivedInvitationsControllerProvider);

    return state.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorStateView(
        message: error is ApiException
            ? error.message
            : 'Something went wrong.',
        onRetry: () =>
            ref.read(receivedInvitationsControllerProvider.notifier).refresh(),
      ),
      data: (invitations) {
        if (invitations.isEmpty) {
          return const EmptyStateView(text: 'No invitations yet.');
        }
        return RefreshIndicator(
          onRefresh: () => ref
              .read(receivedInvitationsControllerProvider.notifier)
              .refresh(),
          child: ListView.builder(
            itemCount: invitations.length,
            itemBuilder: (context, index) {
              final invitation = invitations[index];
              return ListTile(
                leading: UserAvatar(
                  avatarUrl: invitation.inviter.avatarUrl,
                  radius: 20,
                ),
                title: Text(invitation.inviter.username),
                subtitle: Text(
                  _statusLabel(invitation.status, forInvitee: true),
                ),
                trailing: invitation.status == InvitationStatus.pending
                    ? _AcceptDeclineButtons(invitationId: invitation.id)
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _AcceptDeclineButtons extends ConsumerWidget {
  const _AcceptDeclineButtons({required this.invitationId});

  final String invitationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          tooltip: 'Accept',
          onPressed: () => ref
              .read(receivedInvitationsControllerProvider.notifier)
              .respond(invitationId, accept: true),
        ),
        IconButton(
          icon: Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
          tooltip: 'Decline',
          onPressed: () => ref
              .read(receivedInvitationsControllerProvider.notifier)
              .respond(invitationId, accept: false),
        ),
      ],
    );
  }
}

class _SentTab extends ConsumerWidget {
  const _SentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sentInvitationsControllerProvider);

    return state.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorStateView(
        message: error is ApiException
            ? error.message
            : 'Something went wrong.',
        onRetry: () =>
            ref.read(sentInvitationsControllerProvider.notifier).refresh(),
      ),
      data: (invitations) {
        if (invitations.isEmpty) {
          return const EmptyStateView(
            text: "You haven't sent any invitations.",
          );
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(sentInvitationsControllerProvider.notifier).refresh(),
          child: ListView.builder(
            itemCount: invitations.length,
            itemBuilder: (context, index) {
              final invitation = invitations[index];
              return ListTile(
                leading: UserAvatar(
                  avatarUrl: invitation.invitee.avatarUrl,
                  radius: 20,
                ),
                title: Text(invitation.invitee.username),
                subtitle: Text(
                  _statusLabel(invitation.status, forInvitee: false),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

String _statusLabel(InvitationStatus status, {required bool forInvitee}) {
  switch (status) {
    case InvitationStatus.pending:
      return forInvitee ? 'Wants to chat with you' : 'Waiting for a response';
    case InvitationStatus.accepted:
      return 'Accepted';
    case InvitationStatus.declined:
      return 'Declined';
  }
}
