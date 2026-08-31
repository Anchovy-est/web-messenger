import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

/// Matches the backend's own cap — checked client-side too so an
/// oversized file fails fast, before uploading.
const int kMaxMediaBytes = 20 * 1024 * 1024;

/// A picked file is still too large even after compression.
class MediaTooLargeException implements Exception {
  const MediaTooLargeException(this.sizeBytes);
  final int sizeBytes;
}

/// Compression itself failed (corrupt file, unsupported codec).
class MediaCompressionFailedException implements Exception {
  const MediaCompressionFailedException();
}

/// Client-side image/video compression ahead of upload. Bytes in,
/// bytes out — works on Web too, where a picked file has no real path.
class MediaCompressionService {
  /// Resizes (longest side capped at 1920px) and re-encodes as JPEG.
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

  /// Re-encodes via the platform's video codec. No Web implementation
  /// exists for this, so on Web the original bytes pass through
  /// unchanged, still subject to the same size cap.
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
