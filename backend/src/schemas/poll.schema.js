const { z } = require('zod');

// Unlike a message's `body`, a poll's question/options are ordinary
// server-readable text (the server needs to tally votes), so they get
// real content validation like any other plaintext field.
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
