part of 'chat_detail_screen.dart';

/// A still-`sending`/`failed` message's [Message.localBytes] is the
/// local, never-encrypted, not-yet-uploaded image/video/audio bytes
/// (nothing's been uploaded yet, or the upload didn't make it) —
/// rendered directly. Every other status means the server has an
/// end-to-end-encrypted copy: [_fetchAndDecrypt] decrypts it after
/// downloading, using whichever key applies to *this* message specifically
/// (see `ChatDetailController.keyForSender` — a 1:1 chat's single shared
/// key regardless of sender, or a group's per-sender pairwise key). No
/// key available yet for this message's sender is shown as a lock icon
/// rather than attempting (and failing) to decrypt.
///
/// Stateful (not a plain build-method fetch) so the fetch+decrypt only
/// ever runs *once*, in [initState] — starting a fresh
/// `Future`/`FutureBuilder` on every rebuild (which a `ConsumerWidget`
/// would do, since `build()` re-runs on any ancestor state change, e.g.
/// every optimistic-send status transition elsewhere in the thread) both
/// re-fetches needlessly and, combined with the loading state's
/// indeterminate spinner scheduling its own continuous animation frames,
/// can make `pumpAndSettle()` in a widget test never observe a settled
/// frame at all.
class _ImageContent extends ConsumerStatefulWidget {
  const _ImageContent({required this.message});

  final Message message;

  static const _size = 220.0;

  @override
  ConsumerState<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends ConsumerState<_ImageContent> {
  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    final message = widget.message;
    final isLocal =
        message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed;
    final hasKey =
        ref
            .read(chatDetailControllerProvider(message.chatId).notifier)
            .keyForSender(message.senderId) !=
        null;
    if (message.mediaUrl != null && !isLocal && hasKey) {
      _future = _fetchAndDecrypt(ref, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isLocal =
        message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed;
    final localBytes = message.localBytes;
    if (!isLocal && message.mediaUrl == null) return const SizedBox.shrink();

    Widget child;
    if (isLocal) {
      if (localBytes == null) return const SizedBox.shrink();
      child = Image.memory(localBytes, fit: BoxFit.cover);
    } else {
      final future = _future;
      if (future == null) {
        child = const Center(child: Icon(Icons.lock_outline));
      } else {
        child = FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingView();
            }
            if (!snapshot.hasData) {
              return const Center(child: Icon(Icons.broken_image_outlined));
            }
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          },
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _ImageContent._size,
        height: _ImageContent._size,
        child: child,
      ),
    );
  }
}

/// Downloads and decrypts a *remote* (already-uploaded) image/video/
/// audio message's bytes. For a 1:1 chat, that's one decrypt with the
/// chat's shared key. A group has no such single shared key — instead,
/// [message.body] carries this device's own wrapped copy of the
/// one-time key the media was actually encrypted with (see
/// `EncryptionService.encryptMediaForRecipients`); that's unwrapped
/// first, using the pairwise key shared with whoever sent it, and *that*
/// (not the sender key itself) is what decrypts the downloaded bytes.
Future<Uint8List> _fetchAndDecrypt(WidgetRef ref, Message message) async {
  final controller = ref.read(
    chatDetailControllerProvider(message.chatId).notifier,
  );
  final senderKey = controller.keyForSender(message.senderId);
  if (senderKey == null) {
    throw StateError('No key available for this message\'s sender yet.');
  }

  final encryptedBytes = await ref
      .read(messageRepositoryProvider)
      .downloadMedia(message.mediaUrl!);
  final encryptionService = ref.read(encryptionServiceProvider);

  if (!controller.isGroup) {
    return encryptionService.decryptBytes(senderKey, encryptedBytes);
  }

  final myId = ref.read(sessionControllerProvider).user?.id;
  final wrappedKeysJson = message.body;
  if (myId == null || wrappedKeysJson == null) {
    throw StateError('No wrapped media key available for this device.');
  }
  final mediaKeyBytes = await encryptionService.unwrapMediaKeyBytes(
    wrappedKeysJson: wrappedKeysJson,
    myUserId: myId,
    senderKey: senderKey,
  );
  if (mediaKeyBytes == null) {
    throw StateError('This device has no entry in the wrapped media key.');
  }
  return encryptionService.decryptBytes(
    SecretKey(mediaKeyBytes),
    encryptedBytes,
  );
}

/// Same local-vs-network-and-encrypted split as [_ImageContent], but a
/// video needs an actual [VideoPlayerController] (asynchronously
/// initialized, and disposed with the widget) rather than a one-shot
/// image load, so this is stateful where that one isn't. Either way, the
/// bytes in hand (local: [Message.localBytes]; remote: decrypted after
/// downloading) go through [PlatformVideoBytesSource] to become a
/// controller — [VideoPlayerController] has no "play these bytes
/// directly" mode, only asset/file/network/content-URI sources, and
/// which of those is actually reachable differs by platform (see
/// lib/core/media/video_bytes_source.dart).
class _VideoContent extends ConsumerStatefulWidget {
  const _VideoContent({required this.message});

  final Message message;

  @override
  ConsumerState<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends ConsumerState<_VideoContent> {
  VideoPlayerController? _controller;
  bool _failed = false;
  PlatformVideoBytesSource? _source;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final isLocal =
        widget.message.status == MessageStatus.sending ||
        widget.message.status == MessageStatus.failed;

    Uint8List bytes;
    if (isLocal) {
      final localBytes = widget.message.localBytes;
      if (localBytes == null) {
        setState(() => _failed = true);
        return;
      }
      bytes = localBytes;
    } else {
      if (widget.message.mediaUrl == null) {
        setState(() => _failed = true);
        return;
      }
      try {
        bytes = await _fetchAndDecrypt(ref, widget.message);
      } catch (_) {
        if (mounted) setState(() => _failed = true);
        return;
      }
    }

    PlatformVideoBytesSource source;
    VideoPlayerController controller;
    try {
      source = await PlatformVideoBytesSource.create(bytes);
      controller = source.controller;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      await controller.initialize();
      if (!mounted) {
        unawaited(controller.dispose());
        unawaited(source.cleanup());
        return;
      }
      setState(() {
        _controller = controller;
        _source = source;
      });
    } catch (_) {
      unawaited(controller.dispose());
      unawaited(source.cleanup());
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    // The decrypted plaintext temp resource (if any — see
    // `_initialize`/`PlatformVideoBytesSource`) shouldn't linger
    // indefinitely once this bubble is gone; best-effort, same as every
    // other cleanup in this app.
    unawaited(_source?.cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        width: 220,
        height: 140,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const SizedBox(width: 220, height: 140, child: LoadingView());
    }
    final aspectRatio = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 220,
        height: 220 / aspectRatio,
        child: GestureDetector(
          onTap: () => setState(
            () => controller.value.isPlaying
                ? controller.pause()
                : controller.play(),
          ),
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle
                    : Icons.play_circle,
                size: 48,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same local-vs-network-and-encrypted split as [_ImageContent]/
/// [_VideoContent], but audio plays directly from bytes ([AudioPlayer]
/// has a real "play these bytes" source, unlike [VideoPlayerController]
/// — see [BytesSource] — so there's no temp file to write or clean up
/// for a received recording). Nothing is decoded/loaded until the user
/// actually taps play, so opening a thread full of voice messages
/// doesn't eagerly download and decrypt every one of them.
class _AudioContent extends ConsumerStatefulWidget {
  const _AudioContent({required this.message});

  final Message message;

  @override
  ConsumerState<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends ConsumerState<_AudioContent> {
  final _player = AudioPlayer();
  Source? _source;
  bool _sourceFailed = false;
  bool _hasStarted = false;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<void> _completeSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
    _prepareSource();
  }

  Future<void> _prepareSource() async {
    final isLocal =
        widget.message.status == MessageStatus.sending ||
        widget.message.status == MessageStatus.failed;
    if (isLocal) {
      final localBytes = widget.message.localBytes;
      if (localBytes == null) {
        setState(() => _sourceFailed = true);
        return;
      }
      setState(() => _source = BytesSource(localBytes));
      return;
    }
    if (widget.message.mediaUrl == null) {
      setState(() => _sourceFailed = true);
      return;
    }
    try {
      final bytes = await _fetchAndDecrypt(ref, widget.message);
      if (!mounted) return;
      setState(() => _source = BytesSource(bytes));
    } catch (_) {
      if (mounted) setState(() => _sourceFailed = true);
    }
  }

  Future<void> _togglePlay() async {
    final source = _source;
    if (source == null) return;
    try {
      if (_playerState == PlayerState.playing) {
        await _player.pause();
        return;
      }
      if (_playerState == PlayerState.completed) {
        await _player.seek(Duration.zero);
      }
      if (!_hasStarted) {
        _hasStarted = true;
        await _player.play(source);
      } else {
        await _player.resume();
      }
    } catch (_) {
      if (mounted) setState(() => _sourceFailed = true);
    }
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _completeSub.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_sourceFailed) {
      return const SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline),
            SizedBox(width: 8),
            Text('Voice message unavailable'),
          ],
        ),
      );
    }
    if (_source == null) {
      return const SizedBox(
        width: 220,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final total = _duration > Duration.zero ? _duration : _position;
    final maxMs = total.inMilliseconds.clamp(1, double.maxFinite.toInt());
    final positionMs = _position.inMilliseconds.clamp(0, maxMs);

    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _playerState == PlayerState.playing
                  ? Icons.pause_circle
                  : Icons.play_circle,
              size: 32,
            ),
            padding: EdgeInsets.zero,
            onPressed: _togglePlay,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: positionMs.toDouble(),
                max: maxMs.toDouble(),
                onChanged: _duration > Duration.zero
                    ? (value) =>
                          _player.seek(Duration(milliseconds: value.toInt()))
                    : null,
              ),
            ),
          ),
          Text(
            _format(total > Duration.zero ? total : _position),
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
