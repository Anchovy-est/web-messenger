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
  // Pre-checks give a specific, field-attributed error for the common
  // case. The `lower(email)`/`lower(username)` unique indexes (see
  // migrations/…init-users-table.js) are the actual correctness
  // guarantee for the rare race between two concurrent registrations —
  // if both pass this check, one insert below will hit a 23505 unique
  // violation, which errorHandler.js turns into a generic 409.
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
  // itself — the user can still request a new code via
  // POST /auth/resend-verification.
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
  // Same error whether the account doesn't exist, is already verified
  // via a different code, or the code is simply wrong/expired — avoids
  // both account enumeration and leaking which specific check failed.
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
  // Always respond the same way regardless of whether the account exists
  // or is already verified — the controller returns a generic 204
  // either way, so this can't be used to probe for registered emails.
  if (user && !user.email_verified_at) {
    await sendVerificationEmail(user);
  }
}

// Issues a fresh access + refresh token pair for a user and persists the
// refresh token's hash so it can be looked up/revoked later.
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
  // Same error for "no such user" and "wrong password" — distinguishing
  // them lets an attacker enumerate registered emails.
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

  // Rotate on every use: the presented token is revoked immediately and
  // a new one issued, so a stolen-but-unused refresh token can only be
  // replayed once before the legitimate client's next refresh fails —
  // a signal that something is wrong, rather than silent indefinite reuse.
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
  // Always behave the same regardless of whether the account exists —
  // otherwise this endpoint becomes an email-enumeration oracle.
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

  // A password reset is a strong signal to end every existing session —
  // if the reset was triggered because credentials leaked, an attacker's
  // still-valid refresh token would otherwise survive the password change.
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
