const { verifyAccessToken } = require('../utils/jwt');
const { ApiError } = require('./errorHandler');

// Reads `Authorization: Bearer <token>`, verifies it, and attaches
// `req.userId` for downstream handlers. Any missing/malformed/expired/
// invalid token is a 401 — no distinction is made (e.g. expired vs.
// tampered) to avoid giving an attacker extra signal.
function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return next(new ApiError(401, 'UNAUTHENTICATED', 'Missing or invalid authorization header.'));
  }

  try {
    const payload = verifyAccessToken(token);
    req.userId = payload.sub;
    next();
  } catch {
    next(new ApiError(401, 'UNAUTHENTICATED', 'Invalid or expired access token.'));
  }
}

module.exports = { authenticate };
