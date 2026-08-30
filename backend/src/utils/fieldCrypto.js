// Transparent field-level encryption at rest for the one profile field
// (users.bio) that isn't end-to-end encrypted. See
// docs/ENCRYPTION.md for the full design and why bio gets this tier
// (server-held key, so the server can still serve it back to profile
// viewers) instead of the client-held-key tier that message/media
// content uses (where the server never holds a key that can decrypt).
//
// AES-256-GCM: authenticated encryption, so a tampered ciphertext (e.g. a
// hand-edited database row) fails to decrypt loudly instead of silently
// returning garbage. The master key ("KEK") comes from env.js, sourced
// from an environment variable — same posture as the JWT secrets — and
// is never written to the database. Losing/rotating this key makes every
// previously-encrypted bio permanently unreadable; that's an accepted
// trade-off of "the key isn't stored anywhere the database's own
// operator can reach it".
const crypto = require('crypto');
const env = require('../config/env');

const ALGORITHM = 'aes-256-gcm';
const NONCE_BYTES = 12;
const KEY = crypto.createHash('sha256').update(env.profileEncryptionKey).digest();

// Wire format: base64(nonce(12) || ciphertext(N) || authTag(16)) — a
// single opaque string, so it fits the existing `bio TEXT` column with no
// schema change. The same envelope shape is used by the Flutter client
// for end-to-end message/media encryption (see
// lib/services/encryption_service.dart), though the two never share a
// key — this is purely a convenient, consistent wire format.
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
    // Not a valid envelope — e.g. a legacy plaintext bio still sitting
    // in the database from before this field was encrypted. Surfacing the
    // raw value would leak old plaintext through what's supposed to be
    // the decrypted view, so this fails safe instead: treat it as
    // unreadable rather than guessing.
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
    // Auth tag mismatch (tampered/corrupted row) — fail safe, same as above.
    return null;
  }
}

module.exports = { encryptField, decryptField };
