/// Reads the bytes behind a locally-recorded audio file — a real path
/// on mobile/desktop, a `blob:` URL on Web.
library;

export 'local_media_bytes_io.dart'
    if (dart.library.js_interop) 'local_media_bytes_web.dart'
    if (dart.library.html) 'local_media_bytes_web.dart';
