// Transparent field-level encryption at rest for the one profile
// field (users.bio) that isn't end-to-end encrypted — it uses a
// server-held key so the server can still serve it back to profile
// viewers, unlike message/media content, where the server never
// holds a usable key.
//
// AES-256-GCM: authenticated, so a tampered ciphertext (e.g. a
// hand-edited row) fails to decrypt loudly instead of returning
// garbage. The master key comes from env.js and is never written to
// the database. Losing/rotating it makes every existing bio
// permanently unreadable — an accepted trade-off of not storing the
// key anywhere the database's own operator can reach it.
const crypto = require('crypto');
const env = require('../config/env');

const ALGORITHM = 'aes-256-gcm';
const NONCE_BYTES = 12;
const KEY = crypto.createHash('sha256').update(env.profileEncryptionKey).digest();

// Wire format: base64(nonce(12) || ciphertext(N) || authTag(16)) — one
// opaque string, fitting the existing `bio TEXT` column with no
// schema change. Same envelope shape the Flutter client uses for
// end-to-end encryption, though the two never share a key.
function encryptField(plaintext) {
  if (plaintext === null || plaintext === undefined) return null;
  const nonce = crypto.randomBytes(NONCE_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, KEY, nonce);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return Buffer.concat([nonce, ciphertext, authTag]).toString('base64');
}

function decryptField(envelope) {
  if (envelope === null || envelope === undefined) return envelope;
  const raw = Buffer.from(envelope, 'base64');
  if (raw.length < NONCE_BYTES + 16) {
    // Not a valid envelope — e.g. a legacy plaintext bio from before
    // this field was encrypted. Fail safe instead of leaking it.
    return null;
  }
  const nonce = raw.subarray(0, NONCE_BYTES);
  const authTag = raw.subarray(raw.length - 16);
  const ciphertext = raw.subarray(NONCE_BYTES, raw.length - 16);
  const decipher = crypto.createDecipheriv(ALGORITHM, KEY, nonce);
  decipher.setAuthTag(authTag);
  try {
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
  } catch {
    // Auth tag mismatch (tampered/corrupted row) — fail safe.
    return null;
  }
}

module.exports = { encryptField, decryptField };
