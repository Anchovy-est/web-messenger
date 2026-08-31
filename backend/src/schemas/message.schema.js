const { z } = require('zod');

// `body` is an opaque end-to-end-encrypted envelope, not plaintext the
// server ever reads — so this only checks shape (nonempty, a generous
// length ceiling), not content. There's no "is this valid ciphertext"
// check, since verifying that would need a key the server never has.
const sendMessageSchema = z.object({
  // `.trim()` is a no-op on real ciphertext; kept so a whitespace-only
  // string still fails as "effectively empty".
  body: z.string().trim().min(1, 'Message cannot be empty.').max(20000, 'Message is too long.'),
});

// Query params arrive as strings — z.coerce turns "50" into 50 and rejects
// anything that doesn't parse as a number at all.
const listMessagesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional().default(50),
  before: z.string().uuid('Invalid cursor.').optional(),
});

// Edited content follows the same rules as new content.
const editMessageSchema = sendMessageSchema;

const messageIdParamsSchema = z.object({
  id: z.string().uuid('Invalid chat id.'),
  messageId: z.string().uuid('Invalid message id.'),
});

// The uploaded file is always encrypted, so the server can't sniff
// its real type from magic bytes — the client has to declare it. A
// client that lies here only breaks decoding for its own recipients.
const sendMediaTypeSchema = z.object({
  type: z.enum(['image', 'video', 'audio'], {
    message: 'type must be image, video, or audio.',
  }),
  // Opaque to the server. Absent for 1:1 media. A group message has
  // no shared chat key, so this carries its one-time media key,
  // wrapped once per recipient, reusing the otherwise-unused `body`
  // column.
  body: z.string().optional(),
});

module.exports = {
  sendMessageSchema,
  listMessagesQuerySchema,
  editMessageSchema,
  messageIdParamsSchema,
  sendMediaTypeSchema,
};
