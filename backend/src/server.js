const http = require('http');
const env = require('./config/env');
const { createApp } = require('./app');
const { attachSocketServer } = require('./sockets');

// A bug that throws outside any request (a stray non-awaited promise, a
// timer callback, etc.) would otherwise crash the process with no more
// than a raw stack trace on stderr — every in-flight request dropped
// with no response at all, and nothing to say why. Logging it plainly
// and exiting lets the container's `restart: unless-stopped` policy
// (docker-compose.yml) bring the process back up clean rather than
// leaving it running in a possibly-corrupted state, which is the safer
// failure mode for a bug we didn't anticipate.
process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
  process.exit(1);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err);
  process.exit(1);
});

const app = createApp();
const httpServer = http.createServer(app);
const io = attachSocketServer(httpServer);
// Lets REST handlers (message.controller.js) broadcast into socket rooms
// after persisting — see sockets/index.js for why the two are split this
// way. Absent when tests exercise `createApp()` directly via supertest.
app.set('io', io);

httpServer.listen(env.port, () => {
  console.log(`mobile-messenger backend listening on port ${env.port} (${env.nodeEnv})`);
});

module.exports = httpServer;
