const jwt = require('jsonwebtoken');
const env = require('../config/env');

function signAccessToken(userId) {
  return jwt.sign({ sub: userId }, env.jwtAccessSecret, {
    expiresIn: env.jwtAccessExpiresIn,
  });
}

// Throws (jsonwebtoken's own errors: TokenExpiredError, JsonWebTokenError)
// on an invalid/expired token — callers should catch and translate to a
// 401, not let it bubble up as a 500.
function verifyAccessToken(token) {
  return jwt.verify(token, env.jwtAccessSecret);
}

module.exports = { signAccessToken, verifyAccessToken };
