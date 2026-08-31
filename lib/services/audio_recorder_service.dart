import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper around the `record` plugin. Voice messages are AAC-LC
/// at 64kbps — plenty for speech, small enough to not need compression.
class AudioRecorderService {
  final _recorder = AudioRecorder();

  /// Checks (and, the first time, prompts for) mic permission.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to a fresh temp file. Caller must have already
  /// checked [hasPermission].
  Future<void> start() async {
    final filename = 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    // No real filesystem on Web — record() ignores the path there anyway.
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

  /// Stops recording and returns the finished file's path — a real
  /// path on mobile/desktop, a `blob:` URL on Web — or null if nothing
  /// was recorded.
  Future<String?> stop() => _recorder.stop();

  /// Stops and discards the in-progress recording.
  Future<void> cancel() => _recorder.cancel();

  Future<bool> isRecording() => _recorder.isRecording();

  void dispose() {
    unawaited(_recorder.dispose());
  }
}
