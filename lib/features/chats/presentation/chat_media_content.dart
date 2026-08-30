part of 'chat_detail_screen.dart';

/// A still-`sending`/`failed` message's [Message.mediaUrl] is a local,
/// never-encrypted file path (nothing's been uploaded yet, or the upload
/// didn't make it) — rendered directly. Every other status means the
/// server has an end-to-end-encrypted copy: [chatKey] decrypts it after
/// downloading, via [messageRepositoryProvider]/
/// [encryptionServiceProvider]. A null [chatKey] here means this chat's
/// key hasn't been derived yet (see `ChatDetailController.chatKey`) —
/// shown as a lock icon rather than attempting (and failing) to decrypt.
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
  const _ImageContent({required this.message, required this.chatKey});

  final Message message;
  final SecretKey? chatKey;

  static const _size = 220.0;

  @override
  ConsumerState<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends ConsumerState<_ImageContent> {
  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    final url = widget.message.mediaUrl;
    final key = widget.chatKey;
    final isLocal =
        widget.message.status == MessageStatus.sending ||
        widget.message.status == MessageStatus.failed;
    if (url != null && !isLocal && key != null) {
      _future = _fetchAndDecrypt(ref, url, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final url = message.mediaUrl;
    if (url == null) return const SizedBox.shrink();
    final isLocal =
        message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed;

    Widget child;
    if (isLocal) {
      child = Image.file(File(url), fit: BoxFit.cover);
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

Future<Uint8List> _fetchAndDecrypt(
  WidgetRef ref,
  String mediaUrl,
  SecretKey chatKey,
) async {
  final encryptedBytes = await ref
      .read(messageRepositoryProvider)
      .downloadMedia(mediaUrl);
  return ref
      .read(encryptionServiceProvider)
      .decryptBytes(chatKey, encryptedBytes);
}

/// Same local-vs-network-and-encrypted split as [_ImageContent], but a
/// video needs an actual [VideoPlayerController] (asynchronously
/// initialized, and disposed with the widget) rather than a one-shot
/// image load, so this is stateful where that one isn't. Decrypted bytes
/// for a network video are written to a temporary file first —
/// [VideoPlayerController] has no "play these bytes directly" mode, only
/// asset/file/network/content-URI sources.
class _VideoContent extends ConsumerStatefulWidget {
  const _VideoContent({required this.message, required this.chatKey});

  final Message message;
  final SecretKey? chatKey;

  @override
  ConsumerState<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends ConsumerState<_VideoContent> {
  VideoPlayerController? _controller;
  bool _failed = false;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final url = widget.message.mediaUrl;
    if (url == null) {
      setState(() => _failed = true);
      return;
    }
    final isLocal =
        widget.message.status == MessageStatus.sending ||
        widget.message.status == MessageStatus.failed;

    VideoPlayerController controller;
    if (isLocal) {
      controller = VideoPlayerController.file(File(url));
    } else {
      final key = widget.chatKey;
      if (key == null) {
        setState(() => _failed = true);
        return;
      }
      try {
        final decryptedBytes = await _fetchAndDecrypt(ref, url, key);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/decrypted-${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        await tempFile.writeAsBytes(decryptedBytes);
        _tempFile = tempFile;
        controller = VideoPlayerController.file(tempFile);
      } catch (_) {
        if (mounted) setState(() => _failed = true);
        return;
      }
    }
    try {
      await controller.initialize();
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      unawaited(controller.dispose());
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    // The decrypted plaintext temp file (if any — see `_initialize`)
    // shouldn't linger on disk indefinitely once this bubble is gone;
    // best-effort, same as every other cleanup in this app.
    final tempFile = _tempFile;
    if (tempFile != null) {
      unawaited(tempFile.delete().catchError((_) => tempFile));
    }
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
  const _AudioContent({required this.message, required this.chatKey});

  final Message message;
  final SecretKey? chatKey;

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
    final url = widget.message.mediaUrl;
    if (url == null) {
      setState(() => _sourceFailed = true);
      return;
    }
    final isLocal =
        widget.message.status == MessageStatus.sending ||
        widget.message.status == MessageStatus.failed;
    if (isLocal) {
      setState(() => _source = DeviceFileSource(url));
      return;
    }
    final key = widget.chatKey;
    if (key == null) {
      setState(() => _sourceFailed = true);
      return;
    }
    try {
      final bytes = await _fetchAndDecrypt(ref, url, key);
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
