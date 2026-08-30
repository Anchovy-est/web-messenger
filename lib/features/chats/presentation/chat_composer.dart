part of 'chat_detail_screen.dart';

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onStartRecording,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onStartRecording;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: 'Attach',
              onPressed: onAttach,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onChanged: onChanged,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Message',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.mic_none),
              tooltip: 'Record a voice message',
              onPressed: onStartRecording,
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.send),
              tooltip: 'Send',
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces [_Composer] while a voice message is being recorded — stop
/// (checkmark) sends what's been recorded so far, cancel (trash)
/// discards it. There is no text field or attach button here; recording
/// is a distinct mode, not something that happens alongside composing
/// text.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.onCancel,
    required this.onStop,
  });

  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Cancel recording',
              onPressed: onCancel,
            ),
            Icon(Icons.fiber_manual_record, color: colors.error, size: 14),
            const SizedBox(width: 8),
            Text('$minutes:$seconds'),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Recording voice message…',
                style: TextStyle(color: colors.outline),
              ),
            ),
            IconButton.filled(
              icon: const Icon(Icons.check),
              tooltip: 'Stop and send',
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}
