part of 'chat_detail_screen.dart';

/// A poll message's body — question, options (each a tappable row with a
/// live proportional bar and vote count), and a footer noting the total
/// vote count and whether votes are public or anonymous. Rendered by
/// `_MessageBubble._buildBody` for a `type: 'poll'` message, in place of
/// the plain `Text` a text message gets.
///
/// Voting/changing/retracting are all the same gesture: tapping an
/// option that isn't yet this device's own vote casts it (or, if
/// something else was already selected, changes it to this one);
/// tapping the option that *is* already this device's own vote retracts
/// it. One row, one action — no separate "confirm"/"retract" button
/// needed.
class _PollContent extends ConsumerStatefulWidget {
  const _PollContent({
    required this.message,
    required this.isMine,
    required this.textColor,
  });

  final Message message;
  final bool isMine;
  final Color textColor;

  @override
  ConsumerState<_PollContent> createState() => _PollContentState();
}

class _PollContentState extends ConsumerState<_PollContent> {
  // Disables every option row for the duration of one vote/retract
  // request — not per-option, since changing a vote touches two options
  // at once (the old one loses a vote, the new one gains it) and this
  // isn't optimistic (see `ChatDetailController.castVote`'s doc
  // comment), so there's a real gap where neither option yet reflects
  // the tap.
  bool _isVoting = false;

  Future<void> _handleTap(Poll poll, PollOption option) async {
    if (_isVoting) return;
    setState(() => _isVoting = true);
    final notifier = ref.read(
      chatDetailControllerProvider(widget.message.chatId).notifier,
    );
    try {
      if (poll.myVoteOptionId == option.id) {
        await notifier.retractVote(widget.message.id, poll.id);
      } else {
        await notifier.castVote(widget.message.id, poll.id, option.id);
      }
    } catch (e) {
      // Not just `on ApiException` — `_isVoting` is already guaranteed
      // to reset either way via `finally` below, but without this an
      // unforeseen failure would still vote/retract *silently*: no
      // SnackBar, nothing wrong-looking on screen, just a tap that
      // quietly did nothing.
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessageFor(e))));
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  void _showVoters(PollOption option) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                option.text,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${option.voteCount} vote${option.voteCount == 1 ? '' : 's'}',
              ),
            ),
            const Divider(height: 1),
            if ((option.voters ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No votes yet.'),
              )
            else
              for (final voter in option.voters!)
                ListTile(
                  leading: UserAvatar(avatarUrl: voter.avatarUrl, radius: 16),
                  title: Text(voter.displayName),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.message.poll;
    // A poll message always carries its poll from the moment it's ever
    // shown (see message.service.js `attachPolls`) — this only guards
    // against the one edge case where it wouldn't: a poll message that
    // was itself soft-deleted, whose `polls` row is gone too. That's
    // already handled one level up, by `_MessageBubble`'s own
    // `isDeleted` tombstone branch, which never reaches this widget at
    // all — so in practice this never renders, but failing safely (not
    // crashing) costs nothing.
    if (poll == null) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.poll_outlined, size: 16, color: widget.textColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.question,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final option in poll.options) ...[
            _PollOptionRow(
              option: option,
              totalVotes: poll.totalVotes,
              isSelected: poll.myVoteOptionId == option.id,
              isMine: widget.isMine,
              textColor: widget.textColor,
              enabled: !_isVoting,
              onTap: () => _handleTap(poll, option),
              onTapVoteCount: !poll.isAnonymous && option.voteCount > 0
                  ? () => _showVoters(option)
                  : null,
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}'
            ' · ${poll.isAnonymous ? 'Anonymous poll' : 'Public poll'}',
            style: TextStyle(
              fontSize: 11,
              color: widget.textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.totalVotes,
    required this.isSelected,
    required this.isMine,
    required this.textColor,
    required this.enabled,
    required this.onTap,
    this.onTapVoteCount,
  });

  final PollOption option;
  final int totalVotes;
  final bool isSelected;
  final bool isMine;
  final Color textColor;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onTapVoteCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fraction = totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
    // `onPrimary` (not a literal white) for a bubble on `colors.primary`
    // (my own messages — see `_MessageBubble`), same theme token that
    // bubble's own status icon/timestamp text already uses — so this
    // still contrasts correctly against `primary` under a theme where
    // that isn't a dark color close to white's natural pairing (e.g.
    // this app's own light Floral theme).
    final accentColor = isMine ? colors.onPrimary : colors.primary;
    final fillColor = accentColor.withValues(alpha: isSelected ? 0.35 : 0.16);
    final borderColor = isSelected
        ? accentColor
        : textColor.withValues(alpha: 0.35);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: textColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option.text,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onTapVoteCount,
                      child: Text(
                        '${option.voteCount}',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          decoration: onTapVoteCount != null
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
