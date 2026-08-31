part of 'chat_detail_screen.dart';

/// A poll message's body — question, options with a live vote bar, and
/// a footer noting the total and public/anonymous. Tapping an unselected
/// option votes (or changes a vote); tapping the selected one retracts
/// it.
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
  // Disables every option row for one vote/retract request — changing a
  // vote touches two options at once, and this isn't optimistic.
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
      // Broad catch — otherwise an unforeseen failure votes/retracts
      // silently, with no SnackBar to show for it.
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
    // Guards a deleted poll message, whose poll row is gone too —
    // already handled by `_MessageBubble`'s tombstone branch, so this
    // is just a safe fallback.
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
    // `onPrimary`, not a literal white, so this still contrasts under a
    // theme where primary isn't dark (e.g. Floral).
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
