import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web: fetches a `blob:` object URL back into bytes.
Future<Uint8List> readLocalMediaBytes(String pathOrUrl) async {
  final response = await http.get(Uri.parse(pathOrUrl));
  return response.bodyBytes;
}
