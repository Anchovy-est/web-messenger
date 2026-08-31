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

// This screen's supporting widgets are split across a handful of `part`
// files rather than one large one — they're implementation details of
// this screen specifically (not reusable elsewhere, unlike the widgets
// under lib/widgets/), so `part`/`part of` keeps them genuinely private
// to this library while still splitting the file up for readability.
// Every name they define is shared with (and visible to) this file and
// each other automatically; none of them have their own `import`s.
part 'chat_message_bubble.dart';
part 'chat_media_content.dart';
part 'chat_composer.dart';
part 'chat_edit_message_dialog.dart';
part 'chat_create_poll_dialog.dart';
part 'chat_poll_bubble.dart';

enum _MessageAction { edit, delete }

enum _Attachment { galleryPhoto, cameraPhoto, galleryVideo, cameraVideo, poll }

/// Recordings shorter than this are discarded rather than sent — a tap
/// that immediately becomes a stop (an accidental double-tap on the mic
/// button, say) shouldn't produce a near-silent voice message.
const _minRecordingDuration = Duration(seconds: 1);

/// Auto-stops (and sends) a recording that's been running this long,
/// mirroring the video picker's own 2-minute cap — a voice message has
/// no reason to run unbounded, and this also keeps the file comfortably
/// under [kMaxMediaBytes] regardless of encoder settings.
const _maxRecordingDuration = Duration(minutes: 5);

/// A single chat's message thread: history + realtime updates via
/// [ChatDetailController], plus a composer to send new ones. Each of my
/// own messages shows its current status — sending, sent, delivered,
/// read, or failed; a failed one can be tapped to retry. The app bar
/// shows "typing…" under the other participant's name while they're
/// composing a reply. Long-pressing one of my own already-sent messages
/// offers Edit and Delete; an edited message is marked "edited" next to
/// its timestamp, and a deleted one renders as a "This message was
/// deleted" placeholder for both the sender and the recipient.
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

  /// Shows a close (✕) button in the app bar when non-null, and calls it
  /// on tap — used only when this screen is one of several simultaneous
  /// panels on a large window (see `AppShell`'s `_MessagingPane`), to
  /// let that panel be dismissed without navigating away from anything
  /// else. `null` (the default) everywhere else — a phone's single,
  /// full-screen chat is left/back-navigated, not "closed", and the
  /// single desktop panel driven directly by the URL has nothing else on
  /// screen to return this closed chat's space to.
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
  // One GlobalKey per rendered message, so a match's bubble — however
  // far up the thread it is — has a BuildContext `_jumpToMessage` can
  // hand to `Scrollable.ensureVisible`. Never pruned: bounded by however
  // many messages this chat has loaded (a single page — see
  // ChatDetailController), so it never grows unbounded either.
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
  /// the message list being built eagerly (see `build`'s `ListView`, not
  /// a lazy `ListView.builder`) — otherwise an off-screen match's
  /// `GlobalKey` would have no `BuildContext` yet to scroll to.
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
    // Fire-and-forget: the outcome (sent/failed) shows up as that
    // message's own status in the thread, not as a return value here —
    // see ChatDetailController.send.
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

  /// Picks and sends an image or video attachment. Picking, compressing,
  /// and uploading all happen here in the screen rather than
  /// the controller — [ChatDetailController.sendImage]/[sendVideo] only
  /// need an already-compressed local file path, so this method is the
  /// one place that owns talking to `image_picker` and
  /// [MediaCompressionService], with every failure mode (cancelled pick,
  /// compression failure, still-too-large-after-compression) surfaced as a
  /// SnackBar rather than a failed-message bubble, since none of those are
  /// things a retry-in-place would fix.
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
            // Polls only make sense with more than one other person to
            // vote — same group-only restriction the backend itself
            // enforces (see backend/src/services/poll.service.js
            // `createPoll`), mirrored here so the option isn't even
            // offered somewhere it would just come back rejected.
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
          // [picked] itself (not just its bytes), not yet read here —
          // on mobile, `compressVideo` re-encodes straight from
          // `picked.path` via the native codec; only on Web (see its own
          // doc comment) does it fall back to reading `picked`'s
          // original bytes at all.
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

  /// Requests microphone permission (via `record`'s own `hasPermission`,
  /// which shows the OS prompt the first time) and, if granted, starts
  /// recording. A denial is shown as a SnackBar rather than left to fail
  /// silently later at "no audio was ever captured" — the composer stays
  /// in its normal, stable state either way, nothing changes UI-wise
  /// until a recording genuinely starts.
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
  /// optimistic-then-resolves-or-fails shape as [ChatDetailController
  /// .sendAudio] gives every other media type, so a failed upload here
  /// gets the exact same "shows failed, tap to retry" treatment images
  /// and videos already have. A recording under
  /// [_minRecordingDuration] is discarded instead of sent — the
  /// composer returns to its normal state either way ("last stable
  /// state"), never left stuck mid-recording.
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
      // Best-effort — a no-op on Web (see `readLocalMediaBytes`'s doc
      // comment: `path` is a `blob:` URL there, not a real file `dart:io`
      // can delete), which is fine: there's nothing meaningful to clean
      // up for a Blob the browser will garbage-collect on its own once
      // nothing references its object URL any longer.
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

  /// Stops and discards the in-progress recording — the composer
  /// returns to normal with no message sent, no error shown (a
  /// deliberate cancel isn't a failure).
  Future<void> _cancelRecording() async {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    try {
      await _audioRecorder.cancel();
    } catch (_) {
      // Best-effort — there's nothing meaningful left to show the user
      // for a cancel that already returns the composer to a clean state
      // regardless of whether the underlying file was actually deleted.
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
            // Editing only makes sense for text — an image/video message
            // has no text body to rewrite.
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
      // Not just `on ApiException` — an unforeseen failure here should
      // still tell the user their delete didn't go through, rather than
      // failing with no visible feedback at all.
      if (!mounted) return;
      final errorMessage = e is ApiException
          ? e.message
          : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  /// Builds one message's bubble, keyed by a per-message [GlobalKey] so
  /// [_jumpToMessage] can scroll to it later regardless of where it is in
  /// the (eagerly-built, see `build`'s `ListView`) thread, and wired up
  /// to the current search state so a matching message highlights the
  /// query text and — for whichever match is currently selected — its
  /// whole bubble.
  Widget _buildMessageTile(
    Message message,
    String? myId,
    MessageSearchState searchState,
  ) {
    final isMine = message.senderId == myId;
    // Only a message the server has actually confirmed, and that isn't
    // already deleted, can be edited or deleted — a still-`sending`/
    // `failed` placeholder has no real id to act on yet, and there's
    // nothing left to edit/delete on a tombstone.
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

  /// A human label for who's currently typing, or `null` if no one is —
  /// "typing…" for a 1:1 chat (unchanged from before groups existed,
  /// since there's only ever one possible "them"), but named for a
  /// group, where "someone other than me" could be any of several
  /// people typing at once.
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

    // Autoscroll whenever the list grows — covers both "I just sent one"
    // and "one arrived over the socket". Skipped while actively searching
    // so a message arriving mid-search doesn't yank the view away from
    // whatever match the user is looking at.
    ref.listen<AsyncValue<List<Message>>>(
      chatDetailControllerProvider(widget.chatId),
      (previous, next) {
        // `.value` rethrows on an error state — `.valueOrNull` is the safe
        // read when all we want is "however many messages we last had".
        final grew =
            (next.valueOrNull?.length ?? 0) >
            (previous?.valueOrNull?.length ?? 0);
        if (grew && !_isSearching) _scrollToBottom();
      },
    );

    // Jump to whichever match the user has navigated to — landing on a
    // fresh search's default match, or wherever prev/next moved to.
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
                // A loading/error state shows a disabled bell rather than
                // hiding the button entirely — "there is a mute control
                // here, it's just not ready yet" is a more honest state
                // than the button flickering in and out of existence.
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
                message: error is ApiException
                    ? error.message
                    : 'Something went wrong.',
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
                // Built eagerly (every message a real widget up front,
                // rather than lazily via ListView.builder) so a search
                // match's GlobalKey always has a BuildContext to jump to
                // with Scrollable.ensureVisible, even for a message far
                // outside the current viewport. Fine at this scale — one
                // loaded page of messages (see ChatDetailController), not
                // an unbounded history.
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
