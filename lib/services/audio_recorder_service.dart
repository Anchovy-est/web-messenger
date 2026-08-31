import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper around the `record` plugin — mirrors
/// [MediaCompressionService]'s role for image/video: the screen owns an
/// instance of this directly (not through Riverpod) and talks to it only
/// in terms of "start/stop/cancel a recording", never touching the
/// plugin's own API surface itself.
///
/// Voice messages are encoded as AAC-LC at a bitrate suited for speech
/// (64kbps mono-ish quality is plenty for a voice message and keeps
/// files small — nowhere near [kMaxMediaBytes] even for a multi-minute
/// recording, unlike images/videos which need real compression to get
/// under that cap).
class AudioRecorderService {
  final _recorder = AudioRecorder();

  /// Checks (and, the first time, prompts for) microphone permission.
  /// `false` means the user denied it — [start] should not be called in
  /// that case; the caller is expected to show that denial rather than
  /// let it fail silently later.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to a fresh temporary file. Caller must already
  /// have confirmed [hasPermission].
  ///
  /// [path_provider] has no Web implementation (there's no real
  /// filesystem to point a temp directory at) — `record`'s own Web
  /// implementation doesn't actually need this argument anyway, since it
  /// records entirely in-browser and returns a `blob:` URL from [stop]
  /// regardless of what `path` was given, so this only calls
  /// [getTemporaryDirectory] on platforms where it works, and passes a
  /// bare filename the rest of the time.
  Future<void> start() async {
    final filename = 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    final path = kIsWeb
        ? filename
        : '${(await getTemporaryDirectory()).path}/$filename';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
  }

  /// Stops recording and returns the path to the finished file — a real
  /// file path on mobile/desktop, a `blob:` object URL on Web (see
  /// [start]'s doc comment) — or `null` if nothing was actually recorded
  /// (e.g. stopped instantly). Either way, the caller reads it back via
  /// `readLocalMediaBytes` (see lib/core/media/local_media_bytes.dart),
  /// which knows which of the two it's looking at.
  Future<String?> stop() => _recorder.stop();

  /// Stops and discards the in-progress recording — used when the user
  /// cancels instead of sending.
  Future<void> cancel() => _recorder.cancel();

  Future<bool> isRecording() => _recorder.isRecording();

  void dispose() {
    unawaited(_recorder.dispose());
  }
}
