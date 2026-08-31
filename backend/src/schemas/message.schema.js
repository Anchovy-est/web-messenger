const { z } = require('zod');

// `body` is an opaque end-to-end-encrypted envelope (base64 of nonce ||
// ciphertext || authTag — see lib/services/encryption_service.dart),
// not plaintext the server ever reads — so this only validates *shape*
// (nonempty, a generous length ceiling as an abuse/DoS guard), not
// content. There's deliberately no "is this really valid ciphertext"
// check: verifying that would require the server to hold a key that can
// decrypt it, which is exactly what end-to-end encryption means it never
// has. 20000 chars comfortably covers the old 4000-character plaintext
// cap even accounting for encryption/encoding overhead and multi-byte
// UTF-8 text, with headroom to spare.
const sendMessageSchema = z.object({
  // `.trim()` is a no-op on real base64 ciphertext (which never has
  // meaningful leading/trailing whitespace) — kept so a whitespace-only
  // string still fails `.min(1)` as "effectively empty", the same
  // guard this had pre-encryption.
  body: z.string().trim().min(1, 'Message cannot be empty.').max(20000, 'Message is too long.'),
});

// Query params arrive as strings — z.coerce turns "50" into 50 and rejects
// anything that doesn't parse as a number at all.
const listMessagesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional().default(50),
  before: z.string().uuid('Invalid cursor.').optional(),
});

// Edited content is held to the same shape as new content — same length
// cap, same "not just whitespace" rule.
const editMessageSchema = sendMessageSchema;

const messageIdParamsSchema = z.object({
  id: z.string().uuid('Invalid chat id.'),
  messageId: z.string().uuid('Invalid message id.'),
});

// The uploaded file for POST /:id/messages/media is always an
// end-to-end-encrypted blob (the client encrypts the compressed
// image/video, or the recorded audio, before it ever leaves the device — see
// lib/services/encryption_service.dart), which means the server can't
// sniff its real content type from magic bytes (ciphertext has no
// meaningful magic bytes) — the client must declare what it is instead.
// This is a real, deliberate reduction in
// what the server can validate, not an oversight: it's the direct,
// unavoidable cost of the server never being able to inspect message
// content, which is the entire point of end-to-end encryption. A client
// that lies about `type` only breaks decoding for its own recipients,
// same trust boundary as any other field a client controls about its own
// message.
const sendMediaTypeSchema = z.object({
  type: z.enum(['image', 'video', 'audio'], {
    message: 'type must be image, video, or audio.',
  }),
  // Opaque to the server either way (see message.service.js
  // `sendMediaMessage`'s doc comment) — absent for a 1:1 chat's media
  // message, exactly as before this field existed. A *group* message
  // has no single shared chat key to encrypt the media with (see
  // lib/services/encryption_service.dart's "Group messaging" section),
  // so the client instead encrypts the media once with a fresh one-time
  // key and rides that key, wrapped once per recipient, along in this
  // field — reusing `body`, otherwise unused for a media message,
  // rather than adding a new column for it.
  body: z.string().optional(),
});

module.exports = {
  sendMessageSchema,
  listMessagesQuerySchema,
  editMessageSchema,
  messageIdParamsSchema,
  sendMediaTypeSchema,
};
