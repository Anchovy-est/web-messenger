import '../config/env.dart';

/// The backend returns media URLs (avatars, and later message
/// attachments) as paths relative to itself — e.g. `/uploads/avatars/…`
/// — rather than baking in a host, since the right host to reach the
/// backend on differs per client (emulator alias, LAN IP, adb-reverse'd
/// localhost, a real domain in production). Resolve against whatever
/// this client is actually configured to talk to.
String resolveMediaUrl(String urlOrPath) {
  if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
    return urlOrPath;
  }
  return '${Env.apiBaseUrl}$urlOrPath';
}
