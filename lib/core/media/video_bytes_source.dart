/// Cross-platform "play these already-decrypted video bytes" —
/// `PlatformVideoBytesSource.create(bytes)` returns a ready
/// `VideoPlayerController` plus a `cleanup()` to release whatever
/// platform resource backs it (a temp file on mobile/desktop, a `blob:`
/// object URL on Web). Used identically by both a not-yet-uploaded
/// local video preview and a decrypted received one (see
/// `chat_media_content.dart`) — the two used to duplicate this logic
/// with each hand-rolling its own file-writing.
library;

export 'video_bytes_source_io.dart'
    if (dart.library.js_interop) 'video_bytes_source_web.dart'
    if (dart.library.html) 'video_bytes_source_web.dart';
