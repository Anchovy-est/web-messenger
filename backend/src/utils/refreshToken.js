const crypto = require('crypto');

// Refresh tokens are already high-entropy random values (not user-chosen
// secrets like passwords), so a fast SHA-256 hash is the right tool here
// — bcrypt's deliberate slowness would just be wasted latency on every
// refresh/logout request. We still never store the raw token, so a DB
// leak alone doesn't hand out working sessions.
function generateRefreshToken() {
  return crypto.randomBytes(48).toString('hex');
}

function hashToken(rawToken) {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

module.exports = { generateRefreshToken, hashToken };
