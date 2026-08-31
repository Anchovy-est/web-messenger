// Integration tests for typing indicators — a pure socket relay, no
// REST endpoint and nothing persisted — against a real listening
// HTTP+socket.io server.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const request = require('supertest');
const { io: ioClient } = require('socket.io-client');

const { createApp } = require('../app');
const { attachSocketServer } = require('../sockets');
const { pool } = require('../config/db');

const app = createApp();
const httpServer = http.createServer(app);
const io = attachSocketServer(httpServer);
app.set('io', io);

const runId = Date.now();
const createdUsernames = [];

async function registerAndLogin(label) {
  const username = `test_${label}_${runId}`.slice(0, 20);
  createdUsernames.push(username);
  const credentials = {
    username,
    email: `test_${label}_${runId}@example.com`,
    password: 'Password123!',
  };
  await request(app).post('/auth/register').send(credentials);
  const res = await request(app)
    .post('/auth/login')
    .send({ email: credentials.email, password: credentials.password });
  return { id: res.body.user.id, username, accessToken: res.body.accessToken };
}

async function createAcceptedChat(inviter, invitee) {
  const sendRes = await request(app)
    .post('/invitations')
    .set('Authorization', `Bearer ${inviter.accessToken}`)
    .send({ inviteeId: invitee.id });
  const invitationId = sendRes.body.invitation.id;
  await request(app)
    .post(`/invitations/${invitationId}/accept`)
    .set('Authorization', `Bearer ${invitee.accessToken}`);
  return sendRes.body.invitation.chatId;
}

let socketPort;

async function listen() {
  if (socketPort) return socketPort;
  await new Promise((resolve) => httpServer.listen(0, resolve));
  socketPort = httpServer.address().port;
  return socketPort;
}

function connectSocket(accessToken, port) {
  const socket = ioClient(`http://localhost:${port}`, {
    auth: { token: accessToken },
    transports: ['websocket'],
    forceNew: true,
  });
  return new Promise((resolve, reject) => {
    socket.on('connect', () => resolve(socket));
    socket.on('connect_error', (err) => reject(err));
  });
}

function waitForEvent(socket, event, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Timed out waiting for "${event}"`)),
      timeoutMs
    );
    socket.once(event, (payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

// For asserting an event does not arrive — a short fixed wait instead
// of waitForEvent's full timeout, so a negative test passes quickly.
function waitForSilence(socket, event, quietMs = 300) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, quietMs);
    socket.once(event, (payload) => {
      clearTimeout(timer);
      reject(new Error(`Expected no "${event}", but got ${JSON.stringify(payload)}`));
    });
  });
}

after(async () => {
  await new Promise((resolve) => {
    io.close();
    httpServer.close(resolve);
  });
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [createdUsernames]);
  }
  await pool.end();
});

test('User A starts typing and User B sees it in real time', async () => {
  const alice = await registerAndLogin('typa1');
  const bob = await registerAndLogin('typb1');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobReceives = waitForEvent(bobSocket, 'typing');
    aliceSocket.emit('typing', { chatId, isTyping: true });
    const payload = await bobReceives;

    assert.equal(payload.chatId, chatId);
    assert.equal(payload.userId, alice.id);
    assert.equal(payload.isTyping, true);
  } finally {
    aliceSocket.close();
    bobSocket.close();
  }
});

test('User A stops typing and the indicator disappears for User B', async () => {
  const alice = await registerAndLogin('typa2');
  const bob = await registerAndLogin('typb2');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const startReceived = waitForEvent(bobSocket, 'typing');
    aliceSocket.emit('typing', { chatId, isTyping: true });
    await startReceived;

    const stopReceived = waitForEvent(bobSocket, 'typing');
    aliceSocket.emit('typing', { chatId, isTyping: false });
    const payload = await stopReceived;

    assert.equal(payload.isTyping, false);
  } finally {
    aliceSocket.close();
    bobSocket.close();
  }
});

test('a typing event is never echoed back to the sender', async () => {
  const alice = await registerAndLogin('typa3');
  const bob = await registerAndLogin('typb3');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  try {
    const aliceHearsNothing = waitForSilence(aliceSocket, 'typing');
    aliceSocket.emit('typing', { chatId, isTyping: true });
    await aliceHearsNothing;
  } finally {
    aliceSocket.close();
  }
});

test('typing events for a chat you are not part of are dropped, not broadcast', async () => {
  const alice = await registerAndLogin('typa4');
  const bob = await registerAndLogin('typb4');
  const outsider = await registerAndLogin('typo4');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const outsiderSocket = await connectSocket(outsider.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobHearsNothing = waitForSilence(bobSocket, 'typing');
    outsiderSocket.emit('typing', { chatId, isTyping: true });
    await bobHearsNothing;
  } finally {
    outsiderSocket.close();
    bobSocket.close();
  }
});

test('typing indicators are never persisted as messages', async () => {
  const alice = await registerAndLogin('typa5');
  const bob = await registerAndLogin('typb5');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const startReceived = waitForEvent(bobSocket, 'typing');
    aliceSocket.emit('typing', { chatId, isTyping: true });
    await startReceived;

    const stopReceived = waitForEvent(bobSocket, 'typing');
    aliceSocket.emit('typing', { chatId, isTyping: false });
    await stopReceived;
  } finally {
    aliceSocket.close();
    bobSocket.close();
  }

  const res = await request(app)
    .get(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.deepEqual(res.body.messages, []);
});
