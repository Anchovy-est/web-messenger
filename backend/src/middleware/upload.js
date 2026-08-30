const multer = require('multer');
const { ApiError } = require('./errorHandler');

// 5MB — deliberately its own constant rather than reusing
// env.maxUploadBytes (which is a general default meant for future
// larger media uploads).
const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

// memoryStorage (not diskStorage) so the service layer can inspect the
// file's actual bytes (see utils/imageType.js) and choose the filename
// itself before anything touches disk, instead of trusting multer to
// have already written a file we might then need to reject.
const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_AVATAR_BYTES },
  fileFilter: (req, file, cb) => {
    // Fast surface-level check on the client-declared type. Not
    // authoritative — see utils/imageType.js for the real check — but
    // rejecting an obviously-wrong declared type here avoids buffering
    // the rest of the upload for nothing.
    if (file.mimetype === 'image/jpeg' || file.mimetype === 'image/png') {
      return cb(null, true);
    }
    cb(new ApiError(400, 'INVALID_FILE_TYPE', 'Only JPEG and PNG images are allowed.'));
  },
});

// 20MB maximum, after compression — the client is expected to have
// already compressed the image/video before it ever reaches this
// endpoint, but the server caps it independently regardless of whether
// that happened, same posture as every other limit in this file: never
// trust the client alone.
const MAX_MEDIA_BYTES = 20 * 1024 * 1024;

// The uploaded file is always an end-to-end-encrypted blob (see
// message.service.js `sendMediaMessage`) rather than a real image/video
// — its Content-Type is whatever the client's HTTP client happens to
// send for opaque bytes (typically `application/octet-stream`), which
// carries no information about the original media type. There's
// deliberately no `fileFilter` MIME allowlist here — filtering on a
// meaningless field would only reject legitimate encrypted uploads for
// no security benefit; the real "what kind of media is this" signal is
// the separate, schema-validated `type` form field (see
// schemas/message.schema.js `sendMediaTypeSchema`). Magic-byte content
// validation isn't possible once the server can't read the bytes — see
// the comment on `sendMediaMessage` for why that's an accepted
// trade-off of encryption, not an oversight. Size is still capped
// exactly as before.
const mediaUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_MEDIA_BYTES },
});

module.exports = { avatarUpload, MAX_AVATAR_BYTES, mediaUpload, MAX_MEDIA_BYTES };
