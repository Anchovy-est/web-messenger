/* eslint-disable camelcase */

// A one-time data migration, not a schema change — bios written before
// this point are still plaintext, since the app only encrypts on the
// next write. This re-encrypts every existing bio in place, using the
// same algorithm as utils/fieldCrypto.js, duplicated inline so the
// migration stays self-contained and doesn't depend on the app's own
// module resolution.
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

// An already-encrypted value base64-decodes to at least 28 bytes
// (nonce+tag); anything shorter is plaintext still needing migration.
// Makes this safe to run more than once without double-encrypting.
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

// Irreversible on purpose: decrypting back to plaintext on rollback
// would defeat the point of encrypting it. Rolling back the feature
// itself means reverting the application code, not un-migrating data.
exports.down = false;
