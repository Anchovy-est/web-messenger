part of 'chat_detail_screen.dart';

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.onRetry,
    this.onLongPress,
  });

  final Message message;
  final bool isMine;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final controller = ref.read(
      chatDetailControllerProvider(message.chatId).notifier,
    );
    // A group message from someone else names its sender — with more
    // than one possible "not me", bubble alignment alone (all a 1:1
    // chat needs, since there's only ever one other participant,
    // already named in the app bar) no longer says who sent it.
    final senderName = (!isMine && controller.isGroup)
        ? controller.participantNames[message.senderId]
        : null;

    if (message.isDeleted) {
      // Same placeholder regardless of who sent it — both the sender and
      // the recipient see "This message was deleted", not two different
      // views of the same event.
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 14, color: colors.outline),
              const SizedBox(width: 6),
              Text(
                'This message was deleted',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: colors.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final failed = message.status == MessageStatus.failed;
    final time = message.createdAt.toLocal();
    final timeLabel =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: failed
            ? colors.errorContainer
            : isMine
            ? colors.primary
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (senderName != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 2),
          ],
          _buildBody(
            failed
                ? colors.onErrorContainer
                : isMine
                ? colors.onPrimary
                : colors.onSurfaceVariant,
          ),
          const SizedBox(height: 2),
          if (failed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 13, color: colors.error),
                const SizedBox(width: 4),
                Text(
                  'Failed to send · tap to retry',
                  style: TextStyle(fontSize: 11, color: colors.error),
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.editedAt != null) ...[
                  Text(
                    'edited',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color:
                          (isMine ? colors.onPrimary : colors.onSurfaceVariant)
                              .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: (isMine ? colors.onPrimary : colors.onSurfaceVariant)
                        .withValues(alpha: 0.7),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _StatusIcon(status: message.status, color: colors.onPrimary),
                ],
              ],
            ),
        ],
      ),
    );

    Widget content = bubble;
    if (failed && onRetry != null) {
      content = InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onRetry,
        child: bubble,
      );
    } else if (onLongPress != null) {
      content = InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: onLongPress,
        child: bubble,
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: content,
    );
  }

  /// The message's actual content, above the status/timestamp row — text
  /// for a plain message, or a thumbnail/player for an image/video one.
  /// [textColor] is whatever the caller already worked out
  /// for this bubble's state (failed/mine/theirs); media content ignores
  /// it since it's a rendered image or video, not colored text.
  Widget _buildBody(Color textColor) {
    switch (message.type) {
      case 'image':
        return _ImageContent(message: message);
      case 'video':
        return _VideoContent(message: message);
      case 'audio':
        return _AudioContent(message: message);
      default:
        return Text(message.body ?? '', style: TextStyle(color: textColor));
    }
  }
}

/// Only ever shown on my own messages — a recipient doesn't see status
/// ticks on messages they received, only on ones they sent.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.color});

  final MessageStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: color.withValues(alpha: 0.7),
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: 14, color: color.withValues(alpha: 0.7));
      case MessageStatus.delivered:
        return Icon(
          Icons.done_all,
          size: 14,
          color: color.withValues(alpha: 0.7),
        );
      case MessageStatus.read:
        return const Icon(
          Icons.done_all,
          size: 14,
          color: Colors.lightBlueAccent,
        );
      case MessageStatus.failed:
        // The bubble itself switches to an error style for `failed` — see
        // _MessageBubble.build — so this case never actually renders.
        return const SizedBox.shrink();
    }
  }
}
