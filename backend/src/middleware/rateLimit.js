// Rate limiting for endpoints where unlimited attempts give an
// attacker a real advantage: guessing a password, or brute-forcing a
// 6-digit OTP within its validity window.
//
// This factory always enforces whatever limit it's given — whether to
// skip it under NODE_ENV=test is decided where it's wired up (see
// auth.routes.js), not here, since a real backend test run fires
// hundreds of auth requests in seconds.
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

// Credential guessing — generous enough a real user mistyping their
// password isn't blocked, tight enough that credential stuffing from
// one IP is impractical.
const loginRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: 'Too many login attempts. Please try again in a few minutes.',
});

// The actual defense against brute-forcing a 6-digit OTP: 10 attempts
// per 15 minutes makes exhausting 1,000,000 possibilities take, on
// average, tens of thousands of years, while still allowing a few
// genuine typo-retries.
const otpRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: 'Too many attempts. Please try again in a few minutes.',
});

// Account-affecting requests that don't involve guessing a secret —
// throttles spam/abuse rather than defending against brute force.
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
