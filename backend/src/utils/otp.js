const crypto = require('crypto');

// A 6-digit numeric code is far more practical to type into a mobile app
// than a long token from a deep link (which would need platform-specific
// Android App Links / iOS Universal Links configuration) — used for both
// email verification and password reset codes.
function generateOtp() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

function hashOtp(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

module.exports = { generateOtp, hashOtp };
