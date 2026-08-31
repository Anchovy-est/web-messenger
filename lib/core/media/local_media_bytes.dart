/// Cross-platform "read the bytes behind this locally-produced media
/// reference" — used only for [AudioRecorderService.stop]'s return
/// value, which is a real file path on mobile/desktop but a `blob:`
/// object URL on Web (the `record` package records entirely in-browser
/// there, with nothing on a real filesystem to point a path at). Image/
/// video picking doesn't need this at all — `XFile.readAsBytes()` is
/// already cross-platform on its own.
library;

export 'local_media_bytes_io.dart'
    if (dart.library.js_interop) 'local_media_bytes_web.dart'
    if (dart.library.html) 'local_media_bytes_web.dart';
