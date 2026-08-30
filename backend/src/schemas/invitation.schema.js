const { z } = require('zod');

const sendInvitationSchema = z.object({
  inviteeId: z.string().uuid('inviteeId must be a valid user id.'),
});

// Optional filter for GET /invitations/received|sent — omitted entirely
// means "all statuses".
const listInvitationsQuerySchema = z.object({
  status: z.enum(['pending', 'accepted', 'declined']).optional(),
});

const invitationIdParamsSchema = z.object({
  id: z.string().uuid('Invalid invitation id.'),
});

module.exports = {
  sendInvitationSchema,
  listInvitationsQuerySchema,
  invitationIdParamsSchema,
};
