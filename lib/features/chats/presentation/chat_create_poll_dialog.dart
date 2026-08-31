part of 'chat_detail_screen.dart';

/// Mirrors the backend's own option-count limits.
const _minPollOptions = 2;
const _maxPollOptions = 10;

/// A modal dialog to create a poll — question, a dynamic list of
/// options, and a public/anonymous choice. Not optimistic: waits for
/// the server to confirm before closing.
class _CreatePollDialog extends ConsumerStatefulWidget {
  const _CreatePollDialog({required this.chatId});

  final String chatId;

  @override
  ConsumerState<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends ConsumerState<_CreatePollDialog> {
  final _questionController = TextEditingController();
  final _optionControllers = [TextEditingController(), TextEditingController()];
  bool _isAnonymous = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= _maxPollOptions) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= _minPollOptions) return;
    setState(() => _optionControllers.removeAt(index).dispose());
  }

  Future<void> _create() async {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (question.isEmpty) {
      setState(() => _error = 'A poll needs a question.');
      return;
    }
    if (options.length < _minPollOptions) {
      setState(() => _error = 'Enter at least $_minPollOptions options.');
      return;
    }
    final uniqueLowercased = options.map((o) => o.toLowerCase()).toSet();
    if (uniqueLowercased.length != options.length) {
      setState(() => _error = 'Options must be unique.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(chatDetailControllerProvider(widget.chatId).notifier)
          .createPoll(
            question: question,
            options: options,
            isAnonymous: _isAnonymous,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Broad catch — see `_EditMessageDialog._save`'s same reasoning.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a poll'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _questionController,
                autofocus: true,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Question',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              for (final (index, controller) in _optionControllers.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          enabled: !_saving,
                          decoration: InputDecoration(
                            labelText: 'Option ${index + 1}',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (_optionControllers.length > _minPollOptions)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove option',
                          onPressed: _saving
                              ? null
                              : () => _removeOption(index),
                        ),
                    ],
                  ),
                ),
              if (_optionControllers.length < _maxPollOptions)
                TextButton.icon(
                  onPressed: _saving ? null : _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Anonymous votes'),
                subtitle: const Text(
                  'Only totals are shown — nobody sees who voted for what.',
                ),
                value: _isAnonymous,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isAnonymous = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _create,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
