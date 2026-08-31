import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web half of `local_media_bytes.dart`'s conditional export —
/// [AudioRecorderService.stop] hands back a `blob:` object URL on Web
/// (the `record` package's own recording, kept entirely in-browser, has
/// no real file path to give), not a file path, so this fetches it back
/// out instead of reading a file. A `blob:` URL is only ever valid
/// within the browser tab that created it, which this always runs in —
/// same trust boundary as the object URL itself.
Future<Uint8List> readLocalMediaBytes(String pathOrUrl) async {
  final response = await http.get(Uri.parse(pathOrUrl));
  return response.bodyBytes;
}
