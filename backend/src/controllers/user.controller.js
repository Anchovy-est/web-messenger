const userService = require('../services/user.service');
const { ApiError } = require('../middleware/errorHandler');

async function getMe(req, res) {
  const user = await userService.getProfile(req.userId);
  res.status(200).json({ user });
}

async function updateMe(req, res) {
  const user = await userService.updateProfile(req.userId, req.body);
  res.status(200).json({ user });
}

async function uploadAvatar(req, res) {
  if (!req.file) {
    throw new ApiError(400, 'FILE_REQUIRED', 'No file was uploaded.');
  }
  const user = await userService.updateAvatar(req.userId, req.file);
  res.status(200).json({ user });
}

async function search(req, res) {
  const users = await userService.searchUsers(req.userId, req.query.q);
  res.status(200).json({ users });
}

async function updatePublicKey(req, res) {
  const user = await userService.updatePublicKey(req.userId, req.body.publicKey);
  res.status(200).json({ user });
}

async function registerPushToken(req, res) {
  await userService.registerPushToken(req.userId, req.body.token, req.body.platform);
  res.status(204).send();
}

async function unregisterPushToken(req, res) {
  await userService.unregisterPushToken(req.userId, req.body.token);
  res.status(204).send();
}

module.exports = {
  getMe,
  updateMe,
  uploadAvatar,
  search,
  updatePublicKey,
  registerPushToken,
  unregisterPushToken,
};
