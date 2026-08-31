import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// Web: no filesystem, so this wraps the bytes in a [web.Blob] and
/// plays them via the resulting `blob:` object URL.
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

  /// Revokes the object URL so the browser can free the Blob.
  Future<void> cleanup() async {
    web.URL.revokeObjectURL(_objectUrl);
  }
}
