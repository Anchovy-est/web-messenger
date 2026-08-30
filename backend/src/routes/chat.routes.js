const { Router } = require('express');
const chatController = require('../controllers/chat.controller');
const messageController = require('../controllers/message.controller');
const { authenticate } = require('../middleware/authenticate');
const { validateBody, validateQuery, validateParams } = require('../middleware/validate');
const { listChatsQuerySchema, chatIdParamsSchema } = require('../schemas/chat.schema');
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

router.get('/:id', validateParams(chatIdParamsSchema), asyncHandler(chatController.getOne));

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
