const { Router } = require('express');
const authController = require('../controllers/auth.controller');
const { validateBody } = require('../middleware/validate');
const { authenticate } = require('../middleware/authenticate');
const {
  loginRateLimiter,
  otpRateLimiter,
  accountActionRateLimiter,
} = require('../middleware/rateLimit');
const {
  registerSchema,
  loginSchema,
  refreshSchema,
  verifyEmailSchema,
  resendVerificationSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
} = require('../schemas/auth.schema');
const { asyncHandler } = require('../middleware/errorHandler');
const env = require('../config/env');

const router = Router();

// A real test run fires hundreds of auth requests in seconds, which
// would rate-limit the test suite itself. Skipped only here, under
// NODE_ENV=test — the limiters themselves have no such awareness.
const passthrough = (req, res, next) => next();
const login = env.isTest ? passthrough : loginRateLimiter;
const otp = env.isTest ? passthrough : otpRateLimiter;
const accountAction = env.isTest ? passthrough : accountActionRateLimiter;

router.post(
  '/register',
  accountAction,
  validateBody(registerSchema),
  asyncHandler(authController.register)
);

router.post(
  '/login',
  login,
  validateBody(loginSchema),
  asyncHandler(authController.login)
);

router.post(
  '/refresh',
  validateBody(refreshSchema),
  asyncHandler(authController.refresh)
);

router.post(
  '/logout',
  validateBody(refreshSchema),
  asyncHandler(authController.logout)
);

router.get('/me', authenticate, asyncHandler(authController.me));

router.post(
  '/verify-email',
  otp,
  validateBody(verifyEmailSchema),
  asyncHandler(authController.verifyEmail)
);

router.post(
  '/resend-verification',
  accountAction,
  validateBody(resendVerificationSchema),
  asyncHandler(authController.resendVerification)
);

router.post(
  '/forgot-password',
  accountAction,
  validateBody(forgotPasswordSchema),
  asyncHandler(authController.forgotPassword)
);

router.post(
  '/reset-password',
  otp,
  validateBody(resetPasswordSchema),
  asyncHandler(authController.resetPassword)
);

module.exports = router;
