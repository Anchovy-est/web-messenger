const { query } = require('../config/db');

async function create({ userId, tokenHash, expiresAt }) {
  const result = await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [userId, tokenHash, expiresAt]
  );
  return result.rows[0];
}

// Only returns a row if it's still usable — expired or already-revoked
// tokens are treated the same as "not found" by callers.
async function findActiveByHash(tokenHash) {
  const result = await query(
    `SELECT * FROM refresh_tokens
     WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()`,
    [tokenHash]
  );
  return result.rows[0] || null;
}

async function revokeByHash(tokenHash) {
  await query(
    'UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1',
    [tokenHash]
  );
}

// Used on password reset: every existing session is logged out, since a
// password change is usually a response to "someone else might have my
// password" — leaving old sessions alive would defeat the point.
async function revokeAllForUser(userId) {
  await query(
    'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
    [userId]
  );
}

module.exports = { create, findActiveByHash, revokeByHash, revokeAllForUser };
