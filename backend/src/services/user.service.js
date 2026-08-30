const fs = require('fs/promises');
const path = require('path');

const userModel = require('../models/user.model');
const pushTokenModel = require('../models/pushToken.model');
const { ApiError } = require('../middleware/errorHandler');
const { detectImageType, EXTENSION_BY_TYPE } = require('../utils/imageType');

const UPLOADS_ROOT = path.join(__dirname, '../../uploads');
const AVATAR_DIR = path.join(UPLOADS_ROOT, 'avatars');

async function getProfile(userId) {
  const user = await userModel.findById(userId);
  if (!user) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }
  return userModel.toPublicUser(user);
}

async function updateProfile(userId, { username, bio }) {
  // Only re-check uniqueness if the username is actually changing —
  // otherwise a user re-saving their own unchanged username would find
  // "themselves" already taken.
  const existing = await userModel.findByUsername(username);
  if (existing && existing.id !== userId) {
    throw new ApiError(409, 'USERNAME_TAKEN', 'Username is already taken.');
  }

  const updated = await userModel.updateProfile(userId, { username, bio });
  if (!updated) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }
  return userModel.toPublicUser(updated);
}

async function updateAvatar(userId, file) {
  // The authoritative check — see utils/imageType.js for why this isn't
  // just trusting file.mimetype (already filtered once in upload.js, but
  // that only looked at the client-declared header).
  const detectedType = detectImageType(file.buffer);
  if (!detectedType) {
    throw new ApiError(
      400,
      'INVALID_FILE_TYPE',
      'Only JPEG and PNG images are allowed.'
    );
  }

  const previousUser = await userModel.findById(userId);
  if (!previousUser) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }

  await fs.mkdir(AVATAR_DIR, { recursive: true });

  const extension = EXTENSION_BY_TYPE[detectedType];
  const filename = `${userId}-${Date.now()}.${extension}`;
  await fs.writeFile(path.join(AVATAR_DIR, filename), file.buffer);

  const relativeUrl = `/uploads/avatars/${filename}`;
  const updated = await userModel.updateAvatarUrl(userId, relativeUrl);

  // Best-effort cleanup of the file this one replaces. Only touches
  // files under our own avatars/ path — if avatar_url ever points
  // somewhere else (e.g. a future external-URL feature), leave it alone.
  const previousUrl = previousUser.avatar_url;
  if (previousUrl && previousUrl.startsWith('/uploads/avatars/')) {
    const previousPath = path.join(UPLOADS_ROOT, previousUrl.replace('/uploads/', ''));
    fs.unlink(previousPath).catch(() => {});
  }

  return userModel.toPublicUser(updated);
}

async function searchUsers(currentUserId, searchTerm) {
  const rows = await userModel.searchUsers({ searchTerm, excludeUserId: currentUserId });
  return rows.map(userModel.toPublicUser);
}

// Registers this user's end-to-end encryption public key. Called by the
// client once per device the first time it has no locally
// stored private key yet (see lib/services/encryption_service.dart) —
// there's no uniqueness or format validation beyond the schema-level
// shape check (see schemas/user.schema.js), since a public key isn't a
// credential the server needs to protect, just data other clients read.
async function updatePublicKey(userId, publicKey) {
  const updated = await userModel.updatePublicKey(userId, publicKey);
  if (!updated) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }
  return userModel.toPublicUser(updated);
}

// Registers (or re-registers) this device's push token — called once at
// login/session-restore and again whenever Firebase rotates the token
// (see lib/services/push_notification_service.dart). No existence check
// against `users` needed here: `req.userId` already came from a verified
// JWT (see middleware/authenticate.js), and the table's own foreign key
// would reject a dangling reference regardless.
async function registerPushToken(userId, token, platform) {
  await pushTokenModel.register(userId, token, platform);
}

// Called by the client's own logout flow (see
// SessionController.logout) so a signed-out device stops receiving
// this user's pushes immediately, rather than until the token happens
// to expire or get replaced by a future login.
async function unregisterPushToken(userId, token) {
  await pushTokenModel.unregister(userId, token);
}

module.exports = {
  getProfile,
  updateProfile,
  updateAvatar,
  searchUsers,
  updatePublicKey,
  registerPushToken,
  unregisterPushToken,
};
