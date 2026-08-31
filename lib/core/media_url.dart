import '../config/env.dart';

/// The backend returns media URLs as paths relative to itself (e.g.
/// `/uploads/avatars/...`) — resolve against whatever host this client
/// is configured to talk to.
String resolveMediaUrl(String urlOrPath) {
  if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
    return urlOrPath;
  }
  return '${Env.apiBaseUrl}$urlOrPath';
}
