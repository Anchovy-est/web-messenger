const { Router } = require('express');
const userController = require('../controllers/user.controller');
const { validateBody, validateQuery } = require('../middleware/validate');
const { authenticate } = require('../middleware/authenticate');
const { avatarUpload } = require('../middleware/upload');
const {
  updateProfileSchema,
  searchQuerySchema,
  updatePublicKeySchema,
  registerPushTokenSchema,
  unregisterPushTokenSchema,
} = require('../schemas/user.schema');
const { asyncHandler } = require('../middleware/errorHandler');

const router = Router();

// NOTE: keep this above any future `/:id`-style route (e.g. GET
// /users/:id for viewing another user's profile) — otherwise Express
// would match "search" as an :id value instead of this route.
router.get(
  '/search',
  authenticate,
  validateQuery(searchQuerySchema),
  asyncHandler(userController.search)
);

router.get('/me', authenticate, asyncHandler(userController.getMe));

router.put(
  '/me',
  authenticate,
  validateBody(updateProfileSchema),
  asyncHandler(userController.updateMe)
);

router.post(
  '/me/avatar',
  authenticate,
  avatarUpload.single('avatar'),
  asyncHandler(userController.uploadAvatar)
);

// Registers/replaces this user's end-to-end encryption public key. PUT
// (not POST) since it's a full replace of a single resource —
// there's only ever one current public key per user, same reasoning as
// PUT /users/me for the profile fields above.
router.put(
  '/me/public-key',
  authenticate,
  validateBody(updatePublicKeySchema),
  asyncHandler(userController.updatePublicKey)
);

// Registers this device's push notification token (see
// push.service.js for where it's actually used). PUT, not POST — same
// "full replace of a single resource" reasoning as the public-key route
// above, except this resource is per-*device* rather than per-user: the
// token itself, not req.userId, is what `pushToken.model.js` upserts on.
router.put(
  '/me/push-token',
  authenticate,
  validateBody(registerPushTokenSchema),
  asyncHandler(userController.registerPushToken)
);

router.delete(
  '/me/push-token',
  authenticate,
  validateBody(unregisterPushTokenSchema),
  asyncHandler(userController.unregisterPushToken)
);

module.exports = router;
