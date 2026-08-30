const authService = require('../services/auth.service');

async function register(req, res) {
  const user = await authService.register(req.body);
  res.status(201).json({ user });
}

async function login(req, res) {
  const result = await authService.login(req.body);
  res.status(200).json(result);
}

async function refresh(req, res) {
  const result = await authService.refresh(req.body);
  res.status(200).json(result);
}

async function logout(req, res) {
  await authService.logout(req.body);
  res.status(204).send();
}

async function me(req, res) {
  const user = await authService.getCurrentUser(req.userId);
  res.status(200).json({ user });
}

async function verifyEmail(req, res) {
  const user = await authService.verifyEmail(req.body);
  res.status(200).json({ user });
}

async function resendVerification(req, res) {
  await authService.resendVerificationEmail(req.body);
  res.status(204).send();
}

async function forgotPassword(req, res) {
  await authService.forgotPassword(req.body);
  res.status(204).send();
}

async function resetPassword(req, res) {
  await authService.resetPassword(req.body);
  res.status(204).send();
}

module.exports = {
  register,
  login,
  refresh,
  logout,
  me,
  verifyEmail,
  resendVerification,
  forgotPassword,
  resetPassword,
};
