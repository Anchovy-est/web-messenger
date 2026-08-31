import 'dart:io';
import 'dart:typed_data';

/// Mobile/desktop: reads a real file path.
Future<Uint8List> readLocalMediaBytes(String pathOrUrl) {
  return File(pathOrUrl).readAsBytes();
}
