const { Router } = require('express');
const chatController = require('../controllers/chat.controller');
const messageController = require('../controllers/message.controller');
const { authenticate } = require('../middleware/authenticate');
const { validateBody, validateQuery, validateParams } = require('../middleware/validate');
const {
  listChatsQuerySchema,
  chatIdParamsSchema,
  createGroupChatSchema,
} = require('../schemas/chat.schema');
const { sendInvitationSchema } = require('../schemas/invitation.schema');
const {
  sendMessageSchema,
  listMessagesQuerySchema,
  editMessageSchema,
  messageIdParamsSchema,
  sendMediaTypeSchema,
} = require('../schemas/message.schema');
const { asyncHandler } = require('../middleware/errorHandler');
const { mediaUpload } = require('../middleware/upload');

const router = Router();

router.use(authenticate);

router.get('/', validateQuery(listChatsQuerySchema), asyncHandler(chatController.list));

// A literal path, not `/:id` — declared ahead of it regardless, since a
// route table reads more safely when the more specific pattern comes
// first, even though Express wouldn't actually confuse the two here
// (this is POST, `/:id`'s neighbors below are all GET/other POSTs with
// more path segments).
router.post(
  '/groups',
  validateBody(createGroupChatSchema),
  asyncHandler(chatController.createGroup)
);

router.get('/:id', validateParams(chatIdParamsSchema), asyncHandler(chatController.getOne));

// Invites one more person to an *existing* group chat — the group
// equivalent of POST /invitations, which only ever starts a brand-new
// 1:1 chat (see invitation.service.js `inviteToChat`'s doc comment for
// why the two are deliberately separate).
router.post(
  '/:id/invitations',
  validateParams(chatIdParamsSchema),
  validateBody(sendInvitationSchema),
  asyncHandler(chatController.inviteToChat)
);

router.post(
  '/:id/archive',
  validateParams(chatIdParamsSchema),
  asyncHandler(chatController.archive)
);

router.post(
  '/:id/unarchive',
  validateParams(chatIdParamsSchema),
  asyncHandler(chatController.unarchive)
);

router.post('/:id/mute', validateParams(chatIdParamsSchema), asyncHandler(chatController.mute));

router.post(
  '/:id/unmute',
  validateParams(chatIdParamsSchema),
  asyncHandler(chatController.unmute)
);

router.get(
  '/:id/messages',
  validateParams(chatIdParamsSchema),
  validateQuery(listMessagesQuerySchema),
  asyncHandler(messageController.list)
);

router.post(
  '/:id/messages',
  validateParams(chatIdParamsSchema),
  validateBody(sendMessageSchema),
  asyncHandler(messageController.send)
);

router.post(
  '/:id/messages/media',
  validateParams(chatIdParamsSchema),
  // multer must run first — it's what parses the multipart body (both
  // the file and the accompanying `type` field) in the first place;
  // validateBody only has something to check once req.body exists.
  mediaUpload.single('file'),
  validateBody(sendMediaTypeSchema),
  asyncHandler(messageController.sendMedia)
);

router.patch(
  '/:id/messages/:messageId',
  validateParams(messageIdParamsSchema),
  validateBody(editMessageSchema),
  asyncHandler(messageController.edit)
);

router.delete(
  '/:id/messages/:messageId',
  validateParams(messageIdParamsSchema),
  asyncHandler(messageController.deleteMessage)
);

router.post(
  '/:id/delivered',
  validateParams(chatIdParamsSchema),
  asyncHandler(messageController.markDelivered)
);

router.post(
  '/:id/read',
  validateParams(chatIdParamsSchema),
  asyncHandler(messageController.markRead)
);

module.exports = router;
