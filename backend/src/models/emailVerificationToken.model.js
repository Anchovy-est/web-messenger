const { query } = require('../config/db');

async function create({ userId, codeHash, expiresAt }) {
  const result = await query(
    `INSERT INTO email_verification_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [userId, codeHash, expiresAt]
  );
  return result.rows[0];
}

// Scoped by user_id (not just the code) since the 6-digit code alone
// isn't globally unique — two users could coincidentally be issued the
// same code at different times.
async function findActive({ userId, codeHash }) {
  const result = await query(
    `SELECT * FROM email_verification_tokens
     WHERE user_id = $1 AND token_hash = $2
       AND used_at IS NULL AND expires_at > now()
     ORDER BY created_at DESC
     LIMIT 1`,
    [userId, codeHash]
  );
  return result.rows[0] || null;
}

async function markUsed(id) {
  await query('UPDATE email_verification_tokens SET used_at = now() WHERE id = $1', [id]);
}

module.exports = { create, findActive, markUsed };
