import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api_exception.dart';
import '../../../core/media/local_media_bytes.dart';
import '../../../core/media/video_bytes_source.dart';
import '../../../models/message.dart';
import '../../../models/poll.dart';
import '../../../providers/core_providers.dart';
import '../../../services/audio_recorder_service.dart';
import '../../../services/media_compression_service.dart';
import '../../../widgets/connection_banner.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/user_avatar.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/chat_providers.dart';
import 'chat_detail_controller.dart';
import 'chat_mute_controller.dart';
import 'message_search_controller.dart';
import 'typing_indicator_controller.dart';

// Supporting widgets split across `part` files — implementation details
// of this screen, not reusable elsewhere, so `part`/`part of` keeps
// them private while still splitting the file up.
part 'chat_message_bubble.dart';
part 'chat_media_content.dart';
part 'chat_composer.dart';
part 'chat_edit_message_dialog.dart';
part 'chat_create_poll_dialog.dart';
part 'chat_poll_bubble.dart';

enum _MessageAction { edit, delete }

enum _Attachment { galleryPhoto, cameraPhoto, galleryVideo, cameraVideo, poll }

/// Recordings shorter than this are discarded rather than sent.
const _minRecordingDuration = Duration(seconds: 1);

/// Auto-stops (and sends) a recording running this long.
const _maxRecordingDuration = Duration(minutes: 5);

/// A single chat's message thread: history + realtime updates, plus a
/// composer. Each of my own messages shows its status; a failed one
/// can be tapped to retry. Long-pressing my own message offers Edit and
/// Delete; a deleted one renders as a tombstone for both sides.
class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.chatId,
    this.title,
    this.avatarUrl,
    this.onClose,
  });

  final String chatId;
  final String? title;
  final String? avatarUrl;

  /// Shows a close (✕) button in the app bar when non-null — used when
  /// this screen is one of several simultaneous panels on a large
  /// window. Null everywhere else.
  final VoidCallback? onClose;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _compressionService = MediaCompressionService();
  final _audioRecorder = AudioRecorderService();
  bool _isRecording = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTicker;

  // --- In-chat message search ---------------------------------------
  bool _isSearching = false;
  final _searchTextController = TextEditingController();
  final _searchFieldFocusNode = FocusNode();
  // One GlobalKey per rendered message, so `_jumpToMessage` always has
  // a BuildContext to scroll to. Never pruned — bounded by one loaded
  // page of messages.
  final _messageKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordingTicker?.cancel();
    _audioRecorder.dispose();
    _searchTextController.dispose();
    _searchFieldFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _isSearching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFieldFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchTextController.clear();
    ref.read(messageSearchControllerProvider(widget.chatId).notifier).clear();
    setState(() => _isSearching = false);
  }

  /// Scrolls the currently-selected search match into view. Relies on
  /// the message list being built eagerly, not lazily.
  void _jumpToMessage(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _messageKeys[messageId]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    // Fire-and-forget — the outcome shows up as the message's own status.
    ref.read(chatDetailControllerProvider(widget.chatId).notifier).send(text);
  }

  void _editMessage(Message message) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _EditMessageDialog(chatId: widget.chatId, message: message),
    );
  }

  void _createPoll() {
    showDialog<void>(
      context: context,
      builder: (_) => _CreatePollDialog(chatId: widget.chatId),
    );
  }

  /// Picks and sends an image or video attachment. Picking and
  /// compressing happen here; every failure mode surfaces as a SnackBar
  /// rather than a failed-message bubble, since none of them are things
  /// a retry-in-place would fix.
  Future<void> _pickAttachment() async {
    final isGroup = ref
        .read(chatDetailControllerProvider(widget.chatId).notifier)
        .isGroup;
    final choice = await showModalBottomSheet<_Attachment>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.pop(context, _Attachment.galleryPhoto),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, _Attachment.cameraPhoto),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video from gallery'),
              onTap: () => Navigator.pop(context, _Attachment.galleryVideo),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record a video'),
              onTap: () => Navigator.pop(context, _Attachment.cameraVideo),
            ),
            // Group-only, mirroring the backend's own restriction.
            if (isGroup)
              ListTile(
                leading: const Icon(Icons.poll_outlined),
                title: const Text('Poll'),
                onTap: () => Navigator.pop(context, _Attachment.poll),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == _Attachment.poll) {
      _createPoll();
      return;
    }

    try {
      switch (choice) {
        case _Attachment.poll:
          return; // handled above — unreachable, but keeps this exhaustive
        case _Attachment.galleryPhoto:
        case _Attachment.cameraPhoto:
          final picked = await ImagePicker().pickImage(
            source: choice == _Attachment.galleryPhoto
                ? ImageSource.gallery
                : ImageSource.camera,
            imageQuality: 90,
          );
          if (picked == null || !mounted) return;
          final originalBytes = await picked.readAsBytes();
          if (!mounted) return;
          final compressed = await _compressionService.compressImage(
            originalBytes,
          );
          if (!mounted) return;
          ref
              .read(chatDetailControllerProvider(widget.chatId).notifier)
              .sendImage(compressed);
        case _Attachment.galleryVideo:
        case _Attachment.cameraVideo:
          final picked = await ImagePicker().pickVideo(
            source: choice == _Attachment.galleryVideo
                ? ImageSource.gallery
                : ImageSource.camera,
            maxDuration: const Duration(minutes: 2),
          );
          if (picked == null || !mounted) return;
          // `picked` itself, not its bytes — compressVideo re-encodes
          // straight from its path on mobile.
          final compressed = await _compressionService.compressVideo(picked);
          if (!mounted) return;
          ref
              .read(chatDetailControllerProvider(widget.chatId).notifier)
              .sendVideo(compressed);
      }
    } on MediaTooLargeException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That file is too large to send, even after compression '
            '(max 20MB).',
          ),
        ),
      );
    } on MediaCompressionFailedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not process that file. Try a different one.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong picking that file.'),
        ),
      );
    }
  }

  /// Requests mic permission and, if granted, starts recording. A
  /// denial shows a SnackBar rather than failing silently later.
  Future<void> _startRecording() async {
    final granted = await _audioRecorder.hasPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone permission is required to record a voice message.',
          ),
        ),
      );
      return;
    }
    try {
      await _audioRecorder.start();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start recording.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingElapsed = Duration.zero;
    });
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordingElapsed += const Duration(seconds: 1));
      if (_recordingElapsed >= _maxRecordingDuration) _stopRecording();
    });
  }

  /// Stops recording and sends the result as a new audio message — same
  /// optimistic shape as other media sends. Discards a recording under
  /// [_minRecordingDuration] instead of sending it.
  Future<void> _stopRecording() async {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    final elapsed = _recordingElapsed;
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    setState(() => _isRecording = false);

    if (path == null) return; // nothing was actually captured
    if (elapsed < _minRecordingDuration) {
      // Best-effort — a no-op on Web, where `path` is a `blob:` URL.
      unawaited(File(path).delete().catchError((_) => File(path!)));
      return;
    }
    try {
      final bytes = await readLocalMediaBytes(path);
      if (!mounted) return;
      ref
          .read(chatDetailControllerProvider(widget.chatId).notifier)
          .sendAudio(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not process that recording.')),
      );
    }
  }

  /// Stops and discards the in-progress recording — no error shown, a
  /// deliberate cancel isn't a failure.
  Future<void> _cancelRecording() async {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    try {
      await _audioRecorder.cancel();
    } catch (_) {
      // Best-effort.
    }
    if (!mounted) return;
    setState(() => _isRecording = false);
  }

  Future<void> _showMessageActions(Message message) async {
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Editing only makes sense for text.
            if (message.type == 'text')
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_MessageAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _MessageAction.edit:
        _editMessage(message);
      case _MessageAction.delete:
        _confirmDelete(message);
      case null:
        break;
    }
  }

  Future<void> _confirmDelete(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(chatDetailControllerProvider(widget.chatId).notifier)
          .deleteMessage(message.id);
    } catch (e) {
      // Broad catch — the user still needs to know the delete failed.
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessageFor(e))));
    }
  }

  /// Builds one message's bubble, keyed by a per-message [GlobalKey] so
  /// [_jumpToMessage] can scroll to it, and wired to the current search
  /// state for highlighting.
  Widget _buildMessageTile(
    Message message,
    String? myId,
    MessageSearchState searchState,
  ) {
    final isMine = message.senderId == myId;
    // Only a confirmed, non-deleted message can be edited or deleted.
    final canModify =
        isMine &&
        !message.isDeleted &&
        const {
          MessageStatus.sent,
          MessageStatus.delivered,
          MessageStatus.read,
        }.contains(message.status);
    return KeyedSubtree(
      key: _messageKeys.putIfAbsent(message.id, GlobalKey.new),
      child: _MessageBubble(
        message: message,
        isMine: isMine,
        searchQuery: searchState.isActive ? searchState.query : null,
        isCurrentMatch: message.id == searchState.selectedMessageId,
        onRetry: message.status == MessageStatus.failed
            ? () {
                final notifier = ref.read(
                  chatDetailControllerProvider(widget.chatId).notifier,
                );
                if (message.type == 'text') {
                  notifier.retry(message.id, message.body ?? '');
                } else {
                  notifier.retryMedia(message.id);
                }
              }
            : null,
        onLongPress: canModify ? () => _showMessageActions(message) : null,
      ),
    );
  }

  /// A human label for who's typing — plain "typing…" for a 1:1 chat,
  /// named for a group.
  String? _typingLabel(Set<String> typingUserIds) {
    if (typingUserIds.isEmpty) return null;
    final controller = ref.read(
      chatDetailControllerProvider(widget.chatId).notifier,
    );
    if (!controller.isGroup) return 'typing…';
    final names =
        typingUserIds
            .map((id) => controller.participantNames[id] ?? 'Someone')
            .toList()
          ..sort();
    return switch (names.length) {
      1 => '${names[0]} is typing…',
      2 => '${names[0]} and ${names[1]} are typing…',
      _ => 'Several people are typing…',
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatDetailControllerProvider(widget.chatId));
    final myId = ref.watch(sessionControllerProvider).user?.id;
    final isGroup = ref
        .read(chatDetailControllerProvider(widget.chatId).notifier)
        .isGroup;
    final typingLabel = _typingLabel(
      ref.watch(typingIndicatorProvider(widget.chatId)),
    );
    final searchState = ref.watch(
      messageSearchControllerProvider(widget.chatId),
    );

    // Autoscroll whenever the list grows, unless actively searching.
    ref.listen<AsyncValue<List<Message>>>(
      chatDetailControllerProvider(widget.chatId),
      (previous, next) {
        final grew =
            (next.valueOrNull?.length ?? 0) >
            (previous?.valueOrNull?.length ?? 0);
        if (grew && !_isSearching) _scrollToBottom();
      },
    );

    // Jump to whichever match the user has navigated to.
    ref.listen<MessageSearchState>(
      messageSearchControllerProvider(widget.chatId),
      (previous, next) {
        final messageId = next.selectedMessageId;
        if (messageId != null && messageId != previous?.selectedMessageId) {
          _jumpToMessage(messageId);
        }
      },
    );

    final muteState = ref.watch(chatMuteControllerProvider(widget.chatId));

    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Close search',
                onPressed: _closeSearch,
              ),
              title: TextField(
                controller: _searchTextController,
                focusNode: _searchFieldFocusNode,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search in this chat',
                  border: InputBorder.none,
                ),
                onChanged: (query) => ref
                    .read(
                      messageSearchControllerProvider(widget.chatId).notifier,
                    )
                    .updateQuery(query),
              ),
              actions: [
                if (searchState.isActive)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        searchState.totalMatches == 0
                            ? '0/0'
                            : '${searchState.selectedIndex + 1}/${searchState.totalMatches}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous match',
                  onPressed: searchState.totalMatches > 0
                      ? () => ref
                            .read(
                              messageSearchControllerProvider(
                                widget.chatId,
                              ).notifier,
                            )
                            .previous()
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next match',
                  onPressed: searchState.totalMatches > 0
                      ? () => ref
                            .read(
                              messageSearchControllerProvider(
                                widget.chatId,
                              ).notifier,
                            )
                            .next()
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear search',
                  onPressed: _closeSearch,
                ),
              ],
            )
          : AppBar(
              title: Row(
                children: [
                  UserAvatar(
                    avatarUrl: widget.avatarUrl,
                    radius: 16,
                    placeholderIcon: isGroup ? Icons.groups : Icons.person,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title ?? 'Chat',
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (typingLabel != null)
                          Text(
                            typingLabel,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search in this chat',
                  onPressed: _openSearch,
                ),
                // A loading/error state shows a disabled bell rather
                // than hiding the button entirely.
                IconButton(
                  icon: Icon(
                    muteState.valueOrNull == true
                        ? Icons.notifications_off
                        : Icons.notifications_none,
                  ),
                  tooltip: muteState.valueOrNull == true
                      ? 'Unmute notifications'
                      : 'Mute notifications',
                  onPressed: muteState.isLoading
                      ? null
                      : () => ref
                            .read(
                              chatMuteControllerProvider(
                                widget.chatId,
                              ).notifier,
                            )
                            .toggle(),
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close chat',
                    onPressed: widget.onClose,
                  ),
              ],
            ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: state.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorStateView(
                message: errorMessageFor(error),
                onRetry: () => ref
                    .read(chatDetailControllerProvider(widget.chatId).notifier)
                    .refresh(),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  );
                }
                // Built eagerly, not lazily, so a search match's
                // GlobalKey always has a BuildContext to jump to. Fine
                // at this scale — one loaded page of messages.
                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    for (final message in messages)
                      _buildMessageTile(message, myId, searchState),
                  ],
                );
              },
            ),
          ),
          _isRecording
              ? _RecordingBar(
                  elapsed: _recordingElapsed,
                  onCancel: _cancelRecording,
                  onStop: _stopRecording,
                )
              : _Composer(
                  controller: _textController,
                  onSend: _send,
                  onAttach: _pickAttachment,
                  onStartRecording: _startRecording,
                  onChanged: (text) => ref
                      .read(
                        chatDetailControllerProvider(widget.chatId).notifier,
                      )
                      .onComposerChanged(text),
                ),
        ],
      ),
    );
  }
}
