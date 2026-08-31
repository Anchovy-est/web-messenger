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
  // Only re-checks uniqueness if the username is actually changing,
  // so re-saving your own unchanged username doesn't find "itself"
  // already taken.
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
  // The authoritative check — upload.js already filtered on the
  // client-declared header, but this looks at the real bytes.
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

  // Best-effort cleanup of the file this replaces. Only touches files
  // under our own avatars/ path.
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

// Registers this user's end-to-end encryption public key. Called once
// per device, the first time it has no stored private key yet. No
// uniqueness check needed — a public key isn't a credential to
// protect, just data other clients read.
async function updatePublicKey(userId, publicKey) {
  const updated = await userModel.updatePublicKey(userId, publicKey);
  if (!updated) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }
  return userModel.toPublicUser(updated);
}

// Registers (or re-registers) this device's push token — called at
// login/session-restore and whenever Firebase rotates the token. No
// existence check needed: `req.userId` came from a verified JWT.
async function registerPushToken(userId, token, platform) {
  await pushTokenModel.register(userId, token, platform);
}

// Called on logout so a signed-out device stops receiving this
// user's pushes immediately, instead of waiting for the token to
// expire or be replaced.
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
