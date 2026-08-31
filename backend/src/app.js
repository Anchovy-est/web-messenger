// Express app assembly, kept separate from server.js so tests can import
// the app without opening a real port or a socket.io server.
const path = require('path');
const express = require('express');
const cors = require('cors');

const env = require('./config/env');
const healthRoutes = require('./routes/health.routes');
const { notFoundHandler, errorHandler } = require('./middleware/errorHandler');

// Empty CORS_ORIGINS (local dev, tests) reflects any origin — cors()'s
// own default with no options object, same behavior this replaces.
// Once set (a real deployment; env.js refuses to start in production
// without it), only those exact origins are allowed, with credentials
// enabled since the client sends an Authorization header.
const corsOptions =
  env.corsOrigins.length > 0 ? { origin: env.corsOrigins, credentials: true } : undefined;

function createApp() {
  const app = express();

  app.use(cors(corsOptions));
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  // Uploaded avatars and message media live under uploads/ and are
  // served as-is — no auth, matching how profile pictures work in any
  // messenger (visible to anyone who has the URL).
  app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

  app.use('/', healthRoutes);
  app.use('/auth', require('./routes/auth.routes'));
  app.use('/users', require('./routes/user.routes'));
  app.use('/invitations', require('./routes/invitation.routes'));
  app.use('/chats', require('./routes/chat.routes'));

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = { createApp };
