import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

/// The backend independently enforces this same cap (see
/// backend/src/middleware/upload.js `MAX_MEDIA_BYTES`) — this is the
/// client-side check so a file that's still too large *after*
/// compression fails fast, locally, with a specific message, instead of
/// uploading 20MB+ only to be rejected by the server.
const int kMaxMediaBytes = 20 * 1024 * 1024;

/// A picked file couldn't be brought under [kMaxMediaBytes] even after
/// compression — distinct from a plain upload failure (which shows as a
/// normal failed-message bubble) since there's no point retrying this
/// one without picking something smaller to begin with.
class MediaTooLargeException implements Exception {
  const MediaTooLargeException(this.sizeBytes);
  final int sizeBytes;
}

/// The compression step itself failed (corrupt file, unsupported codec,
/// platform plugin error) — distinct from [MediaTooLargeException]
/// because the cause here isn't "too big", it's "couldn't be processed
/// at all".
class MediaCompressionFailedException implements Exception {
  const MediaCompressionFailedException();
}

/// Client-side image/video compression ahead of upload — wraps two
/// different platform-channel plugins behind one small, bytes-in/
/// bytes-out interface so `ChatDetailScreen` doesn't need to know which
/// one applies to which picked file, or which platform it's running on.
///
/// Bytes in, bytes out (not file paths) on purpose: it's what makes this
/// work on Web too, where a picked `XFile`'s `.path` is a `blob:` URL
/// rather than something `dart:io`/these plugins' path-based APIs can
/// read at all — `XFile.readAsBytes()` is the one thing about a picked
/// file that's actually cross-platform.
class MediaCompressionService {
  /// Resizes (longest side capped at 1920px) and re-encodes as JPEG at
  /// reduced quality — `flutter_image_compress`'s bytes-in/bytes-out API
  /// works identically on every platform this app runs on, Web included.
  Future<Uint8List> compressImage(Uint8List bytes) async {
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 80,
      minWidth: 1920,
      minHeight: 1920,
    );
    if (result.isEmpty) {
      throw const MediaCompressionFailedException();
    }
    if (result.length > kMaxMediaBytes) {
      throw MediaTooLargeException(result.length);
    }
    return result;
  }

  /// Re-encodes at a reduced bitrate/resolution via the platform's video
  /// codec (MediaCodec on Android, AVFoundation on iOS) — real
  /// transcoding, not just a duration/quality cap at picking time.
  ///
  /// `video_compress` has no Web implementation at all (it's a native-
  /// codec plugin with nothing to bind to in a browser) — on Web,
  /// [source]'s original bytes pass through unchanged instead of being
  /// re-encoded, still subject to the same [kMaxMediaBytes] cap below,
  /// so an oversized video on Web fails fast with the same
  /// [MediaTooLargeException] a mobile user would see after compression
  /// fell short, rather than uploading for nothing.
  Future<Uint8List> compressVideo(XFile source) async {
    if (kIsWeb) {
      final bytes = await source.readAsBytes();
      if (bytes.length > kMaxMediaBytes) {
        throw MediaTooLargeException(bytes.length);
      }
      return bytes;
    }

    final info = await VideoCompress.compressVideo(
      source.path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
    );
    final path = info?.path;
    if (path == null) {
      throw const MediaCompressionFailedException();
    }

    final bytes = await File(path).readAsBytes();
    if (bytes.length > kMaxMediaBytes) {
      throw MediaTooLargeException(bytes.length);
    }
    return bytes;
  }
}
