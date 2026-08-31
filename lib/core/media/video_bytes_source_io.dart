import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Mobile/desktop: writes decrypted bytes to a temp file for the player.
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

  /// Deletes the temp file once playback is done with it.
  Future<void> cleanup() async {
    await _file.delete().catchError((_) => _file);
  }
}
