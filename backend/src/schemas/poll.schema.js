const { z } = require('zod');

// Unlike `sendMessageSchema`'s `body` (an opaque end-to-end-encrypted
// envelope the server never reads), a poll's question and options are
// ordinary server-readable text — see the migration's doc comment on
// `polls` for why that's an unavoidable, deliberate trade-off, not an
// oversight. So these get real content validation, the same as any
// plaintext field elsewhere in this API (a display name, a bio).
const createPollSchema = z.object({
  question: z
    .string()
    .trim()
    .min(1, 'A poll needs a question.')
    .max(300, 'Question is too long.'),
  options: z
    .array(
      z.string().trim().min(1, 'An option cannot be empty.').max(150, 'Option is too long.')
    )
    .min(2, 'A poll needs at least 2 options.')
    .max(10, 'A poll can have at most 10 options.')
    .refine((options) => new Set(options.map((o) => o.toLowerCase())).size === options.length, {
      message: 'Options must be unique.',
    }),
  isAnonymous: z.boolean().optional().default(false),
});

const pollIdParamsSchema = z.object({
  id: z.string().uuid('Invalid chat id.'),
  pollId: z.string().uuid('Invalid poll id.'),
});

const castVoteSchema = z.object({
  optionId: z.string().uuid('Invalid option id.'),
});

module.exports = { createPollSchema, pollIdParamsSchema, castVoteSchema };
