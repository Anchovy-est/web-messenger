import 'dart:io';

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

/// Client-side image/video compression (Phases 18/19) ahead of upload —
/// wraps two different platform-channel plugins behind one small
/// interface so `ChatDetailScreen` doesn't need to know which one
/// applies to which picked file.
class MediaCompressionService {
  /// Resizes (longest side capped at 1920px) and re-encodes as JPEG at
  /// reduced quality. Returns the path to the compressed file — deliberately
  /// a *new* file next to the source, so the original picked file is left
  /// untouched (its path is also what a failed send's retry re-attempts
  /// with, so it must keep meaning "this exact file").
  Future<String> compressImage(String sourcePath) async {
    final targetPath = _siblingPath(sourcePath, 'jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      quality: 80,
      minWidth: 1920,
      minHeight: 1920,
    );
    if (result == null) {
      throw const MediaCompressionFailedException();
    }

    final size = await File(result.path).length();
    if (size > kMaxMediaBytes) {
      throw MediaTooLargeException(size);
    }
    return result.path;
  }

  /// Re-encodes at a reduced bitrate/resolution via the platform's video
  /// codec (MediaCodec on Android, AVFoundation on iOS) — real
  /// transcoding, not just a duration/quality cap at picking time.
  Future<String> compressVideo(String sourcePath) async {
    final info = await VideoCompress.compressVideo(
      sourcePath,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
    );
    final path = info?.path;
    if (path == null) {
      throw const MediaCompressionFailedException();
    }

    final size = await File(path).length();
    if (size > kMaxMediaBytes) {
      throw MediaTooLargeException(size);
    }
    return path;
  }

  String _siblingPath(String sourcePath, String extension) {
    final dir = File(sourcePath).parent.path;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '$dir/compressed_$stamp.$extension';
  }
}
