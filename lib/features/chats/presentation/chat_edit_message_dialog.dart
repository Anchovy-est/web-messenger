part of 'chat_detail_screen.dart';

/// A modal dialog to edit one of my own messages. Not optimistic: stays
/// open with an inline error on failure (e.g. the
/// backend rejects it — see `ChatDetailController.editMessage`) instead
/// of silently reverting like a failed *send* does, since here there's no
/// separate per-message status indicator to fall back to showing it.
class _EditMessageDialog extends ConsumerStatefulWidget {
  const _EditMessageDialog({required this.chatId, required this.message});

  final String chatId;
  final Message message;

  @override
  ConsumerState<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends ConsumerState<_EditMessageDialog> {
  late final _controller = TextEditingController(
    text: widget.message.body ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Message cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(chatDetailControllerProvider(widget.chatId).notifier)
          .editMessage(widget.message.id, text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Deliberately not just `on ApiException` — anything unforeseen
      // (a crypto library hiccup encrypting the edit, say) must still
      // land here and reset `_saving`, or this dialog is stuck showing
      // a spinner on a permanently disabled Save button for the rest of
      // its life, with no way out but dismissing it and losing the edit.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : 'Something went wrong.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit message'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            enabled: !_saving,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
