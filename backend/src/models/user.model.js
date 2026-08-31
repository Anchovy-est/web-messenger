// Data-access layer for `users`. Business rules (e.g. "is this email
// already taken") live in auth.service.js, not here — keeping the two
// separate makes validation testable without a database, and SQL
// testable without Express.
const { query } = require('../config/db');
const { encryptField, decryptField } = require('../utils/fieldCrypto');

const PUBLIC_COLUMNS = `
  id, username, email, display_name, avatar_url, bio, public_key,
  email_verified_at, created_at, updated_at
`;

async function findByEmail(email) {
  const result = await query(
    'SELECT * FROM users WHERE lower(email) = lower($1)',
    [email]
  );
  return result.rows[0] || null;
}

async function findByUsername(username) {
  const result = await query(
    'SELECT * FROM users WHERE lower(username) = lower($1)',
    [username]
  );
  return result.rows[0] || null;
}

async function findById(id) {
  const result = await query('SELECT * FROM users WHERE id = $1', [id]);
  return result.rows[0] || null;
}

async function markEmailVerified(userId) {
  const result = await query(
    `UPDATE users SET email_verified_at = now(), updated_at = now()
     WHERE id = $1
     RETURNING ${PUBLIC_COLUMNS}`,
    [userId]
  );
  return result.rows[0] || null;
}

// Both fields always come together from the profile edit screen, so
// this replaces both rather than doing a partial update. `bio` is
// encrypted at rest — even an empty bio encrypts to a real envelope,
// so "no bio" doesn't leak length as plaintext.
async function updateProfile(userId, { username, bio }) {
  const result = await query(
    `UPDATE users SET username = $1, bio = $2, updated_at = now()
     WHERE id = $3
     RETURNING ${PUBLIC_COLUMNS}`,
    [username, encryptField(bio), userId]
  );
  return result.rows[0] || null;
}

// Registers/replaces this user's X25519 identity public key, used for
// end-to-end encryption. Stored in plain text — a public key isn't
// sensitive. Idempotent: the client calls this on every login where
// it doesn't already have this exact key cached.
async function updatePublicKey(userId, publicKey) {
  const result = await query(
    `UPDATE users SET public_key = $1, updated_at = now()
     WHERE id = $2
     RETURNING ${PUBLIC_COLUMNS}`,
    [publicKey, userId]
  );
  return result.rows[0] || null;
}

async function updateAvatarUrl(userId, avatarUrl) {
  const result = await query(
    `UPDATE users SET avatar_url = $1, updated_at = now()
     WHERE id = $2
     RETURNING ${PUBLIC_COLUMNS}`,
    [avatarUrl, userId]
  );
  return result.rows[0] || null;
}

// `%` and `_` are SQL LIKE wildcards — escape them so a search term
// is always treated as literal text.
function escapeLikePattern(input) {
  return input.replace(/[\\%_]/g, (match) => `\\${match}`);
}

// Username matches anywhere in the string; email requires an exact
// match, so partial email search can't be used to harvest addresses.
// The searching user is always excluded from their own results.
async function searchUsers({ searchTerm, excludeUserId, limit = 20 }) {
  const likePattern = `%${escapeLikePattern(searchTerm)}%`;
  const result = await query(
    `SELECT ${PUBLIC_COLUMNS} FROM users
     WHERE id != $1
       AND (
         lower(username) LIKE lower($2) ESCAPE '\\'
         OR lower(email) = lower($3)
       )
     ORDER BY username
     LIMIT $4`,
    [excludeUserId, likePattern, searchTerm, limit]
  );
  return result.rows;
}

async function updatePasswordHash(userId, passwordHash) {
  await query(
    'UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2',
    [passwordHash, userId]
  );
}

async function createUser({ username, email, passwordHash, displayName }) {
  const result = await query(
    `INSERT INTO users (username, email, password_hash, display_name)
     VALUES ($1, $2, $3, $4)
     RETURNING ${PUBLIC_COLUMNS}`,
    [username, email, passwordHash, displayName || username]
  );
  return result.rows[0];
}

// Strips password_hash and anything else not meant for API responses,
// and decrypts `bio` back to plaintext. Always send user data through
// this before it reaches a response body.
function toPublicUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    username: row.username,
    email: row.email,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    bio: decryptField(row.bio),
    publicKey: row.public_key,
    emailVerified: Boolean(row.email_verified_at),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

module.exports = {
  findByEmail,
  findByUsername,
  findById,
  createUser,
  markEmailVerified,
  updateProfile,
  updateAvatarUrl,
  updatePublicKey,
  searchUsers,
  updatePasswordHash,
  toPublicUser,
};
