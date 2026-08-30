const { z } = require('zod');

// Query params arrive as strings — z.enum keeps this an explicit
// "true"/"false" choice rather than accepting arbitrary truthy strings.
const listChatsQuerySchema = z.object({
  archived: z.enum(['true', 'false']).optional().default('false'),
});

const chatIdParamsSchema = z.object({
  id: z.string().uuid('Invalid chat id.'),
});

module.exports = { listChatsQuerySchema, chatIdParamsSchema };
