import 'dart:io';
import 'dart:typed_data';

/// Mobile/desktop half of `local_media_bytes.dart`'s conditional export
/// — [AudioRecorderService.stop] hands back a real file path here, so
/// reading it is a plain `dart:io` read.
Future<Uint8List> readLocalMediaBytes(String pathOrUrl) {
  return File(pathOrUrl).readAsBytes();
}
