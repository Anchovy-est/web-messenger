import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../features/invitations/data/invitation_providers.dart';
import '../../../models/user.dart';
import '../../../widgets/empty_state_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/user_avatar.dart';
import 'search_controller.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  // Matches the backend's own limit.
  static const _maxQueryLength = 100;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: _maxQueryLength,
          decoration: const InputDecoration(
            hintText: 'Search by username or email',
            border: InputBorder.none,
            counterText: '',
          ),
          onChanged: (value) {
            setState(() {}); // refresh hasQuery for the empty-state below
            ref.read(searchControllerProvider.notifier).onQueryChanged(value);
          },
        ),
      ),
      body: SafeArea(child: _buildBody(context, state, hasQuery)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<User>> state,
    bool hasQuery,
  ) {
    if (!hasQuery) {
      return const EmptyStateView(
        icon: Icons.search,
        text: 'Search for someone by username or email',
      );
    }

    if (state.isLoading) {
      return const LoadingView();
    }

    if (state.hasError) {
      return EmptyStateView(
        icon: Icons.error_outline,
        text: errorMessageFor(state.error!),
      );
    }

    final users = state.value ?? const [];
    if (users.isEmpty) {
      return const EmptyStateView(
        icon: Icons.person_off_outlined,
        text: 'No users found.',
      );
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) => _SearchResultTile(user: users[index]),
    );
  }
}

enum _InviteStatus { idle, sending, sent }

class _SearchResultTile extends ConsumerStatefulWidget {
  const _SearchResultTile({required this.user});

  final User user;

  @override
  ConsumerState<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends ConsumerState<_SearchResultTile> {
  _InviteStatus _status = _InviteStatus.idle;

  Future<void> _sendInvitation() async {
    setState(() => _status = _InviteStatus.sending);
    try {
      await ref
          .read(invitationRepositoryProvider)
          .sendInvitation(widget.user.id);
      if (!mounted) return;
      setState(() => _status = _InviteStatus.sent);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to ${widget.user.username}.')),
      );
    } catch (e) {
      // Broad catch — an unforeseen failure must still reset `_status`,
      // not leave the button stuck spinning forever.
      if (!mounted) return;
      setState(() => _status = _InviteStatus.idle);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessageFor(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return ListTile(
      leading: UserAvatar(avatarUrl: user.avatarUrl, radius: 20),
      title: Text(user.username),
      subtitle: Text(
        (user.bio == null || user.bio!.isEmpty) ? user.email : user.bio!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: switch (_status) {
        _InviteStatus.idle => TextButton(
          onPressed: _sendInvitation,
          child: const Text('Invite'),
        ),
        _InviteStatus.sending => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        _InviteStatus.sent => Icon(
          Icons.check,
          color: Theme.of(context).colorScheme.primary,
        ),
      },
    );
  }
}
