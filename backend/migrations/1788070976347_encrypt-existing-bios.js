/* eslint-disable camelcase */

// A one-time data migration, not a schema change — `users.bio` used to
// be plain text; from this point on user.model.js always writes/reads
// it through utils/fieldCrypto.js's
// AES-256-GCM envelope. Without this pass, any bio set before today
// would keep sitting in the database as plaintext forever (the app code
// only encrypts on the *next* write), which directly defeats the point.
// This re-encrypts every existing non-null bio in place, using the exact
// same algorithm/key-derivation as utils/fieldCrypto.js — duplicated
// inline (rather than `require`d from src/) so this migration doesn't
// depend on how the app's own module resolution or dotenv loading
// happens to behave under node-pg-migrate's runner; migrations should be
// self-contained.
const crypto = require('crypto');

const ALGORITHM = 'aes-256-gcm';
const NONCE_BYTES = 12;

function keyFrom(secret) {
  return crypto.createHash('sha256').update(secret).digest();
}

function encryptField(key, plaintext) {
  const nonce = crypto.randomBytes(NONCE_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, key, nonce);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return Buffer.concat([nonce, ciphertext, authTag]).toString('base64');
}

// A value already produced by encryptField() base64-decodes to at least
// nonce+tag (28) bytes; anything shorter than that couldn't possibly be
// one of our envelopes, so it's treated as plaintext needing migration.
// This makes the migration safe to run more than once (e.g. a retried
// deploy) without double-encrypting already-migrated rows.
function looksEncrypted(value) {
  try {
    return Buffer.from(value, 'base64').length >= NONCE_BYTES + 16;
  } catch {
    return false;
  }
}

exports.shorthands = undefined;

exports.up = async (pgm) => {
  const secret =
    process.env.PROFILE_ENCRYPTION_KEY ||
    (process.env.NODE_ENV === 'test' ? 'S4LyjPYqjukQ3eB8yz9VCzcMVAKl/IfGjctV2PprAtY=' : undefined);
  if (!secret) {
    throw new Error(
      'PROFILE_ENCRYPTION_KEY must be set to run this migration (see .env.example).'
    );
  }
  const key = keyFrom(secret);

  const { rows } = await pgm.db.query(
    'SELECT id, bio FROM users WHERE bio IS NOT NULL'
  );
  for (const row of rows) {
    if (looksEncrypted(row.bio)) continue; // already migrated
    const encrypted = encryptField(key, row.bio);
    await pgm.db.query('UPDATE users SET bio = $1 WHERE id = $2', [encrypted, row.id]);
  }
};

// Deliberately irreversible: decrypting back to plaintext on a rollback
// would mean writing sensitive data back out in the clear, which is
// exactly what this feature exists to prevent. Rolling back the
// *encryption feature* means reverting the application code; the data
// migration itself doesn't un-migrate.
exports.down = false;
