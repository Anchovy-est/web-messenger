/// Plays already-decrypted video bytes — `create(bytes)` returns a
/// ready `VideoPlayerController` plus a `cleanup()` for whatever
/// resource backs it (a temp file, or a Web object URL).
library;

export 'video_bytes_source_io.dart'
    if (dart.library.js_interop) 'video_bytes_source_web.dart'
    if (dart.library.html) 'video_bytes_source_web.dart';
