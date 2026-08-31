const crypto = require('crypto');

// Refresh tokens are already high-entropy, unlike passwords, so a fast
// SHA-256 hash is enough — bcrypt's slowness would just be wasted
// latency here. The raw token is still never stored.
function generateRefreshToken() {
  return crypto.randomBytes(48).toString('hex');
}

function hashToken(rawToken) {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

module.exports = { generateRefreshToken, hashToken };
