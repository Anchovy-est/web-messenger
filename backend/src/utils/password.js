const bcrypt = require('bcryptjs');

// Cost factor 12 is a reasonable balance for 2026 hardware — high enough
// to make offline brute-forcing expensive, low enough to keep register/
// login latency well under a second.
const SALT_ROUNDS = 12;

function hashPassword(plain) {
  return bcrypt.hash(plain, SALT_ROUNDS);
}

function verifyPassword(plain, hash) {
  return bcrypt.compare(plain, hash);
}

module.exports = { hashPassword, verifyPassword };
