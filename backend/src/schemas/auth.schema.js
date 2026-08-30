const { z } = require('zod');

// Username: 3-20 chars, letters/digits/underscore only — safe to display
// and to use in URLs (including user search) without escaping concerns.
const username = z
  .string()
  .trim()
  .min(3, 'Username must be at least 3 characters.')
  .max(20, 'Username must be at most 20 characters.')
  .regex(
    /^[a-zA-Z0-9_]+$/,
    'Username may only contain letters, numbers, and underscores.'
  );

const email = z.string().trim().toLowerCase().email('Enter a valid email address.');

// bcrypt (and bcryptjs) silently truncate at 72 bytes, so cap the input
// length there rather than let a long password be accepted but only
// partially checked. The four character-class rules below mirror the
// client's own validator (see lib/core/utils/password_rules.dart) — kept
// in sync by hand since the two run in different languages, but this is
// the actual enforcement: a client that skipped/bypassed its own check
// still can't register or reset a password that doesn't meet it.
const password = z
  .string()
  .min(8, 'Password must be at least 8 characters.')
  .max(72, 'Password must be at most 72 characters.')
  .regex(/[a-z]/, 'Password must contain at least one lowercase letter.')
  .regex(/[A-Z]/, 'Password must contain at least one uppercase letter.')
  .regex(/[0-9]/, 'Password must contain at least one number.')
  .regex(
    /[^A-Za-z0-9]/,
    'Password must contain at least one special character.'
  );

const registerSchema = z.object({
  username,
  email,
  password,
  displayName: z.string().trim().min(1).max(50).optional(),
});

const loginSchema = z.object({
  email,
  password: z.string().min(1, 'Password is required.'),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1, 'Refresh token is required.'),
});

const otpCode = z
  .string()
  .trim()
  .length(6, 'Enter the 6-digit code.')
  .regex(/^[0-9]+$/, 'Enter the 6-digit code.');

const verifyEmailSchema = z.object({
  email,
  code: otpCode,
});

const resendVerificationSchema = z.object({ email });

const forgotPasswordSchema = z.object({ email });

const resetPasswordSchema = z.object({
  email,
  code: otpCode,
  newPassword: password,
});

module.exports = {
  registerSchema,
  loginSchema,
  refreshSchema,
  verifyEmailSchema,
  resendVerificationSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
};
