const { Router } = require('express');
const userController = require('../controllers/user.controller');
const { validateBody, validateQuery } = require('../middleware/validate');
const { authenticate } = require('../middleware/authenticate');
const { avatarUpload } = require('../middleware/upload');
const {
  updateProfileSchema,
  searchQuerySchema,
  updatePublicKeySchema,
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

// Registers/replaces this user's E2EE public key. PUT since it's a
// full replace of a single resource, same reasoning as PUT /users/me.
router.put(
  '/me/public-key',
  authenticate,
  validateBody(updatePublicKeySchema),
  asyncHandler(userController.updatePublicKey)
);

module.exports = router;
