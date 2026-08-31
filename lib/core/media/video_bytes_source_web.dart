import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// Web half of `video_bytes_source.dart`'s conditional export —
/// `dart:io`/`path_provider` have no real filesystem to write a temp
/// file to on Web (see this app's other platform-conditional media
/// helpers), so instead this wraps the decrypted bytes in a [web.Blob]
/// and plays them via the `blob:` object URL that yields, through
/// [VideoPlayerController.networkUrl] — the one video-player constructor
/// that works on every platform, browsers included.
class PlatformVideoBytesSource {
  PlatformVideoBytesSource._(this.controller, this._objectUrl);

  final VideoPlayerController controller;
  final String _objectUrl;

  static Future<PlatformVideoBytesSource> create(Uint8List bytes) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );
    final objectUrl = web.URL.createObjectURL(blob);
    final controller = VideoPlayerController.networkUrl(Uri.parse(objectUrl));
    return PlatformVideoBytesSource._(controller, objectUrl);
  }

  /// Revokes the object URL so the browser can free the underlying
  /// Blob — the Web equivalent of deleting the temp file the mobile/
  /// desktop implementation writes.
  Future<void> cleanup() async {
    web.URL.revokeObjectURL(_objectUrl);
  }
}
