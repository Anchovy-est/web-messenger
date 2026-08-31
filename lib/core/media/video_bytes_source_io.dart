import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Mobile/desktop half of `video_bytes_source.dart`'s conditional export
/// — decrypted video bytes have to land somewhere real before
/// [VideoPlayerController] can play them (it has no "play these bytes
/// directly" constructor), so this writes them to a temp file exactly
/// like this app always has.
class PlatformVideoBytesSource {
  PlatformVideoBytesSource._(this.controller, this._file);

  final VideoPlayerController controller;
  final File _file;

  static Future<PlatformVideoBytesSource> create(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/video-${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    await file.writeAsBytes(bytes);
    return PlatformVideoBytesSource._(VideoPlayerController.file(file), file);
  }

  /// The decrypted plaintext temp file shouldn't linger on disk
  /// indefinitely once playback is done with it — best-effort, same as
  /// every other cleanup in this app.
  Future<void> cleanup() async {
    await _file.delete().catchError((_) => _file);
  }
}
