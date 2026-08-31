const { z } = require('zod');

// Query params arrive as strings — z.enum keeps this an explicit
// "true"/"false" choice rather than accepting arbitrary truthy strings.
const listChatsQuerySchema = z.object({
  archived: z.enum(['true', 'false']).optional().default('false'),
});

const chatIdParamsSchema = z.object({
  id: z.string().uuid('Invalid chat id.'),
});

// 49 + the creator themselves = a 50-person cap, a sane upper bound for
// a group chat with no real product requirement pointing at a specific
// number — big enough for any realistic use of this feature, small
// enough that one request can't be used to spam invitations at scale.
const createGroupChatSchema = z.object({
  name: z
    .string()
    .trim()
    .min(1, 'Group name is required.')
    .max(100, 'Group name must be at most 100 characters.'),
  participantIds: z
    .array(z.string().uuid('Each participant id must be a valid user id.'))
    .min(1, 'Select at least one participant.')
    .max(49, 'A group can have at most 50 participants, including you.'),
});

module.exports = { listChatsQuerySchema, chatIdParamsSchema, createGroupChatSchema };
