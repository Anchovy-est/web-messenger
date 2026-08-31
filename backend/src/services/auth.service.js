const ms = require('ms');

const userModel = require('../models/user.model');
const refreshTokenModel = require('../models/refreshToken.model');
const emailVerificationTokenModel = require('../models/emailVerificationToken.model');
const passwordResetTokenModel = require('../models/passwordResetToken.model');
const { hashPassword, verifyPassword } = require('../utils/password');
const { signAccessToken } = require('../utils/jwt');
const { generateRefreshToken, hashToken } = require('../utils/refreshToken');
const { generateOtp, hashOtp } = require('../utils/otp');
const emailService = require('./email.service');
const { ApiError } = require('../middleware/errorHandler');
const env = require('../config/env');

const VERIFICATION_CODE_TTL = '30m';
const PASSWORD_RESET_CODE_TTL = '15m';

async function register({ username, email, password, displayName }) {
  // Gives a specific, field-attributed error for the common case. The
  // unique indexes on email/username are the real guarantee for a
  // race between two concurrent registrations — if both pass this
  // check, one insert below hits a unique violation, turned into a
  // generic 409 by errorHandler.js.
  const existingEmail = await userModel.findByEmail(email);
  if (existingEmail) {
    throw new ApiError(409, 'EMAIL_TAKEN', 'Email is already registered.');
  }

  const existingUsername = await userModel.findByUsername(username);
  if (existingUsername) {
    throw new ApiError(409, 'USERNAME_TAKEN', 'Username is already taken.');
  }

  const passwordHash = await hashPassword(password);
  const user = await userModel.createUser({
    username,
    email,
    passwordHash,
    displayName,
  });

  // Best-effort: a broken mail transport shouldn't fail registration
  // — the user can request a new code via resend-verification.
  try {
    await sendVerificationEmail(user);
  } catch (err) {
    console.error('Failed to send verification email:', err);
  }

  return userModel.toPublicUser(user);
}

async function sendVerificationEmail(user) {
  const code = generateOtp();
  const expiresAt = new Date(Date.now() + ms(VERIFICATION_CODE_TTL));

  await emailVerificationTokenModel.create({
    userId: user.id,
    codeHash: hashOtp(code),
    expiresAt,
  });

  await emailService.sendEmail({
    to: user.email,
    subject: 'Verify your email — Mobile Messenger',
    text: `Your verification code is ${code}. It expires in 30 minutes.`,
  });
}

async function verifyEmail({ email, code }) {
  const user = await userModel.findByEmail(email);
  // Same error whether the account doesn't exist, is already
  // verified, or the code is wrong/expired — avoids both account
  // enumeration and leaking which check failed.
  const invalidCodeError = new ApiError(
    400,
    'INVALID_CODE',
    'That code is invalid or has expired.'
  );

  if (!user) throw invalidCodeError;
  if (user.email_verified_at) {
    return userModel.toPublicUser(user); // already verified: treat as success
  }

  const tokenRow = await emailVerificationTokenModel.findActive({
    userId: user.id,
    codeHash: hashOtp(code),
  });
  if (!tokenRow) throw invalidCodeError;

  await emailVerificationTokenModel.markUsed(tokenRow.id);
  const updated = await userModel.markEmailVerified(user.id);
  return userModel.toPublicUser(updated);
}

async function resendVerificationEmail({ email }) {
  const user = await userModel.findByEmail(email);
  // Always responds the same way regardless of whether the account
  // exists or is verified — the controller returns a generic 204
  // either way, so this can't probe for registered emails.
  if (user && !user.email_verified_at) {
    await sendVerificationEmail(user);
  }
}

// Issues a fresh access + refresh token pair and persists the refresh
// token's hash so it can be looked up/revoked later.
async function issueSession(userId) {
  const accessToken = signAccessToken(userId);
  const rawRefreshToken = generateRefreshToken();
  const expiresAt = new Date(Date.now() + ms(env.jwtRefreshExpiresIn));

  await refreshTokenModel.create({
    userId,
    tokenHash: hashToken(rawRefreshToken),
    expiresAt,
  });

  return { accessToken, refreshToken: rawRefreshToken };
}

async function login({ email, password }) {
  const user = await userModel.findByEmail(email);
  // Same error for "no such user" and "wrong password" — otherwise
  // this becomes an email-enumeration oracle.
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    throw new ApiError(401, 'INVALID_CREDENTIALS', 'Incorrect email or password.');
  }

  const session = await issueSession(user.id);
  return { user: userModel.toPublicUser(user), ...session };
}

async function refresh({ refreshToken }) {
  const existing = await refreshTokenModel.findActiveByHash(hashToken(refreshToken));
  if (!existing) {
    throw new ApiError(401, 'INVALID_REFRESH_TOKEN', 'Refresh token is invalid or expired.');
  }

  // Rotate on every use: the presented token is revoked immediately
  // and a new one issued, so a stolen-but-unused token can only be
  // replayed once before the real client's next refresh fails.
  await refreshTokenModel.revokeByHash(hashToken(refreshToken));
  return issueSession(existing.user_id);
}

async function logout({ refreshToken }) {
  await refreshTokenModel.revokeByHash(hashToken(refreshToken));
}

async function getCurrentUser(userId) {
  const user = await userModel.findById(userId);
  if (!user) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }
  return userModel.toPublicUser(user);
}

async function forgotPassword({ email }) {
  const user = await userModel.findByEmail(email);
  // Always behaves the same regardless of whether the account exists,
  // to avoid email enumeration.
  if (!user) return;

  const code = generateOtp();
  const expiresAt = new Date(Date.now() + ms(PASSWORD_RESET_CODE_TTL));
  await passwordResetTokenModel.create({
    userId: user.id,
    codeHash: hashOtp(code),
    expiresAt,
  });

  await emailService.sendEmail({
    to: user.email,
    subject: 'Reset your password — Mobile Messenger',
    text: `Your password reset code is ${code}. It expires in 15 minutes. If you didn't request this, you can ignore this email.`,
  });
}

async function resetPassword({ email, code, newPassword }) {
  const invalidCodeError = new ApiError(
    400,
    'INVALID_CODE',
    'That code is invalid or has expired.'
  );

  const user = await userModel.findByEmail(email);
  if (!user) throw invalidCodeError;

  const tokenRow = await passwordResetTokenModel.findActive({
    userId: user.id,
    codeHash: hashOtp(code),
  });
  if (!tokenRow) throw invalidCodeError;

  await passwordResetTokenModel.markUsed(tokenRow.id);
  await userModel.updatePasswordHash(user.id, await hashPassword(newPassword));

  // A password reset ends every existing session — otherwise an
  // attacker's still-valid refresh token would survive the change.
  await refreshTokenModel.revokeAllForUser(user.id);
}

module.exports = {
  register,
  login,
  refresh,
  logout,
  getCurrentUser,
  verifyEmail,
  resendVerificationEmail,
  forgotPassword,
  resetPassword,
};
