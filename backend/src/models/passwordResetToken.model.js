const { query } = require('../config/db');

async function create({ userId, codeHash, expiresAt }) {
  const result = await query(
    `INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [userId, codeHash, expiresAt]
  );
  return result.rows[0];
}

// Scoped by user_id for the same reason as email_verification_tokens —
// a 6-digit code isn't globally unique across users.
async function findActive({ userId, codeHash }) {
  const result = await query(
    `SELECT * FROM password_reset_tokens
     WHERE user_id = $1 AND token_hash = $2
       AND used_at IS NULL AND expires_at > now()
     ORDER BY created_at DESC
     LIMIT 1`,
    [userId, codeHash]
  );
  return result.rows[0] || null;
}

async function markUsed(id) {
  await query('UPDATE password_reset_tokens SET used_at = now() WHERE id = $1', [id]);
}

module.exports = { create, findActive, markUsed };
