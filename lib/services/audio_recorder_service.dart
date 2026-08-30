import 'dart:async';

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
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
  }

  /// Stops recording and returns the path to the finished file, or
  /// `null` if nothing was actually recorded (e.g. stopped instantly).
  Future<String?> stop() => _recorder.stop();

  /// Stops and discards the in-progress recording — used when the user
  /// cancels instead of sending.
  Future<void> cancel() => _recorder.cancel();

  Future<bool> isRecording() => _recorder.isRecording();

  void dispose() {
    unawaited(_recorder.dispose());
  }
}
