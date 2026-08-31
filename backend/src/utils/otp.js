const crypto = require('crypto');

// A 6-digit code is easier to type than a deep-link token — used for
// both email verification and password reset.
function generateOtp() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

function hashOtp(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

module.exports = { generateOtp, hashOtp };
