// Rate limiting for endpoints where an attacker gets a real advantage
// from unlimited attempts: guessing a password (`/auth/login`), or
// brute-forcing a 6-digit OTP (`/auth/verify-email`,
// `/auth/reset-password` — see utils/otp.js, only 1,000,000 possible
// codes) within its 15–30 minute validity window. Without this, an
// unauthenticated script could exhaustively try every code for a known
// email well before it expires — for `/auth/reset-password` specifically,
// that's a full account takeover with no need to ever see the reset
// email at all.
//
// Deliberately has no opinion here about test environments — this
// factory always enforces whatever limit it's given (see
// rateLimit.test.js, which relies on that). Skipping it entirely under
// `NODE_ENV=test` is a decision made where these are actually wired up
// (see auth.routes.js), not baked in here — a real backend test run
// fires hundreds of auth requests against the same in-process app within
// seconds, which is a load pattern this middleware is not meant to
// judge.
const rateLimit = require('express-rate-limit');

function createRateLimiter({ windowMs, max, message }) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
      res.status(429).json({ error: { code: 'RATE_LIMITED', message } });
    },
  });
}

// Credential guessing — generous enough that a real user mistyping their
// password a few times never gets blocked, tight enough that automated
// credential stuffing against one IP is impractical.
const loginRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: 'Too many login attempts. Please try again in a few minutes.',
});

// OTP verification — the actual defense against brute-forcing a 6-digit
// code within its validity window (see the module doc comment above).
// 10 attempts per 15 minutes makes exhausting 1,000,000 possibilities
// from one IP take, on average, tens of thousands of years — while still
// giving a real user several genuine typo-retries.
const otpRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: 'Too many attempts. Please try again in a few minutes.',
});

// Account-affecting requests that don't involve guessing a secret
// (register, resend a verification email, request a password reset) —
// looser than the two above, this is about throttling spam/abuse
// (e.g. using someone else's email as a registration/reset target
// repeatedly) rather than defending against brute force.
const accountActionRateLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 8,
  message: 'Too many requests. Please try again later.',
});

module.exports = {
  createRateLimiter,
  loginRateLimiter,
  otpRateLimiter,
  accountActionRateLimiter,
};
