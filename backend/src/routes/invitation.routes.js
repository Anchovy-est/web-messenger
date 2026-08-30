const { Router } = require('express');
const invitationController = require('../controllers/invitation.controller');
const { authenticate } = require('../middleware/authenticate');
const { validateBody, validateQuery, validateParams } = require('../middleware/validate');
const {
  sendInvitationSchema,
  listInvitationsQuerySchema,
  invitationIdParamsSchema,
} = require('../schemas/invitation.schema');
const { asyncHandler } = require('../middleware/errorHandler');

const router = Router();

router.use(authenticate);

router.post('/', validateBody(sendInvitationSchema), asyncHandler(invitationController.send));

router.get(
  '/received',
  validateQuery(listInvitationsQuerySchema),
  asyncHandler(invitationController.listReceived)
);

router.get(
  '/sent',
  validateQuery(listInvitationsQuerySchema),
  asyncHandler(invitationController.listSent)
);

router.post(
  '/:id/accept',
  validateParams(invitationIdParamsSchema),
  asyncHandler(invitationController.accept)
);

router.post(
  '/:id/decline',
  validateParams(invitationIdParamsSchema),
  asyncHandler(invitationController.decline)
);

module.exports = router;
