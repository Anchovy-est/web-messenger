const multer = require('multer');
const { ApiError } = require('./errorHandler');

// Its own constant rather than reusing env.maxUploadBytes, which is a
// general default for larger media uploads.
const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

// memoryStorage so the service layer can inspect the file's real
// bytes and pick its own filename before anything touches disk.
const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_AVATAR_BYTES },
  fileFilter: (req, file, cb) => {
    // Quick check on the client-declared type. Not authoritative —
    // see utils/imageType.js for the real check — just avoids
    // buffering an obviously-wrong upload for nothing.
    if (file.mimetype === 'image/jpeg' || file.mimetype === 'image/png') {
      return cb(null, true);
    }
    cb(new ApiError(400, 'INVALID_FILE_TYPE', 'Only JPEG and PNG images are allowed.'));
  },
});

// 20MB after compression — the client is expected to compress first,
// but the server caps it independently regardless, like every other
// limit here: never trust the client alone.
const MAX_MEDIA_BYTES = 20 * 1024 * 1024;

// The upload is always encrypted ciphertext, not a real image/video,
// so its Content-Type carries no real information and there's no
// fileFilter MIME allowlist here. The real "what kind of media"
// signal is the separate, schema-validated `type` form field. Size
// is still capped as usual.
const mediaUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_MEDIA_BYTES },
});

module.exports = { avatarUpload, MAX_AVATAR_BYTES, mediaUpload, MAX_MEDIA_BYTES };
