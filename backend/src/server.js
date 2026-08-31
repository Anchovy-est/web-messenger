const http = require('http');
const env = require('./config/env');
const { createApp } = require('./app');
const { attachSocketServer } = require('./sockets');

// A bug outside any request (a stray promise, a timer) would otherwise
// crash silently. Log it and exit so the container's restart policy
// brings the process back up clean instead of running corrupted.
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
// Lets REST handlers broadcast into socket rooms after persisting.
// Absent when tests exercise createApp() directly via supertest.
app.set('io', io);

httpServer.listen(env.port, () => {
  console.log(`mobile-messenger backend listening on port ${env.port} (${env.nodeEnv})`);
});

module.exports = httpServer;
