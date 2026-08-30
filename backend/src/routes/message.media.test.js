// Integration tests for image/video messages against a real Postgres
// connection, the real filesystem (backend/uploads/messages), and a
// real listening HTTP+socket.io server (for the realtime-broadcast
// tests) — see auth.routes.test.js for how to run this suite.
//
// The uploaded file is always an opaque end-to-end-encrypted blob (the
// real image/video bytes never reach the server — see
// lib/services/encryption_service.dart), so these tests use arbitrary
// "ciphertext-shaped" buffers rather than real JPEG/MP4 fixtures, and
// assert the server stores/relays them byte-for-byte without being able
// to (or trying to) inspect what's inside. The kind of media (image vs.
// video) is a client-declared `type` form field instead of something
// sniffed from magic bytes.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('fs/promises');
const path = require('path');
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
const uploadedMediaPaths = [];
const UPLOADS_ROOT = path.join(__dirname, '../..');

function trackMediaUrl(res) {
  if (res.body?.message?.mediaUrl) {
    uploadedMediaPaths.push(path.join(UPLOADS_ROOT, res.body.message.mediaUrl));
  }
}

// Stand-ins for "an encrypted image/video blob" — what actually flows
// over this endpoint post-Phase-20 is ciphertext, which is indistinguishable
// from any other opaque byte sequence; there's no meaningful "valid
// ciphertext" fixture to construct beyond "some bytes of the right size".
const ENCRYPTED_IMAGE_BLOB = Buffer.from('not-really-a-jpeg-just-ciphertext-bytes');
const ENCRYPTED_VIDEO_BLOB = Buffer.from('not-really-an-mp4-either-also-ciphertext');
const ENCRYPTED_AUDIO_BLOB = Buffer.from('not-really-an-m4a-either-also-ciphertext');
const OVERSIZED_BLOB = Buffer.alloc(21 * 1024 * 1024, 0x42);

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

// `type` rides alongside the file as a second multipart form field —
// exactly what the Flutter client sends (see
// lib/features/chats/data/message_repository.dart `sendMediaMessage`).
function sendMedia(token, chatId, buffer, { filename, type }) {
  const req = request(app)
    .post(`/chats/${chatId}/messages/media`)
    .set('Authorization', `Bearer ${token}`)
    .attach('file', buffer, { filename, contentType: 'application/octet-stream' });
  return type === undefined ? req : req.field('type', type);
}

function listMessages(token, chatId) {
  return request(app).get(`/chats/${chatId}/messages`).set('Authorization', `Bearer ${token}`);
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

after(async () => {
  await new Promise((resolve) => {
    io.close();
    httpServer.close(resolve);
  });
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [createdUsernames]);
  }
  await pool.end();
  await Promise.all(uploadedMediaPaths.map((p) => fs.unlink(p).catch(() => {})));
});

// --- Images (encrypted) -------------------------------------------------

test('sending an encrypted image blob creates an image message with a stored mediaUrl', async () => {
  const alice = await registerAndLogin('imga1');
  const bob = await registerAndLogin('imgb1');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
    filename: 'photo.jpg',
    type: 'image',
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.message.type, 'image');
  assert.equal(res.body.message.senderId, alice.id);
  assert.equal(res.body.message.body, null);
  // A generic extension, not `.jpg` — the server never learns the real
  // media type, only the client-declared `type` field (see the message
  // itself, not the filename on disk).
  assert.match(res.body.message.mediaUrl, /^\/uploads\/messages\/.+\.enc$/);
  trackMediaUrl(res);

  const staticRes = await request(app).get(res.body.message.mediaUrl);
  assert.equal(staticRes.status, 200);
  // The server stores/serves the ciphertext byte-for-byte — it's opaque
  // to the server, but must round-trip exactly for the recipient's
  // client to be able to decrypt it.
  assert.ok(Buffer.from(staticRes.body).equals(ENCRYPTED_IMAGE_BLOB));
});

test('an image message is persisted and visible to the receiver, ciphertext intact', async () => {
  const alice = await registerAndLogin('imga3');
  const bob = await registerAndLogin('imgb3');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMedia(alice.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
    filename: 'photo.jpg',
    type: 'image',
  });
  trackMediaUrl(sendRes);

  const bobList = await listMessages(bob.accessToken, chatId);
  assert.equal(bobList.body.messages.length, 1);
  assert.equal(bobList.body.messages[0].type, 'image');
  assert.equal(bobList.body.messages[0].mediaUrl, sendRes.body.message.mediaUrl);
});

test('rejects a missing type field', async () => {
  const alice = await registerAndLogin('imga4');
  const bob = await registerAndLogin('imgb4');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
    filename: 'photo.jpg',
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('rejects a type field that is not image, video, or audio', async () => {
  const alice = await registerAndLogin('imga5');
  const bob = await registerAndLogin('imgb5');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
    filename: 'photo.jpg',
    type: 'document',
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('rejects a file over the 20MB cap', async () => {
  const alice = await registerAndLogin('imga6');
  const bob = await registerAndLogin('imgb6');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, OVERSIZED_BLOB, {
    filename: 'huge.jpg',
    type: 'image',
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_TOO_LARGE');
});

test('with no file returns 400 FILE_REQUIRED', async () => {
  const alice = await registerAndLogin('imga7');
  const bob = await registerAndLogin('imgb7');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await request(app)
    .post(`/chats/${chatId}/messages/media`)
    .set('Authorization', `Bearer ${alice.accessToken}`)
    .field('type', 'image');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_REQUIRED');
});

test('requires authentication', async () => {
  const res = await request(app)
    .post('/chats/00000000-0000-0000-0000-000000000000/messages/media')
    .field('type', 'image')
    .attach('file', ENCRYPTED_IMAGE_BLOB, {
      filename: 'photo.jpg',
      contentType: 'application/octet-stream',
    });
  assert.equal(res.status, 401);
});

test('a user outside the chat cannot send media into it (404)', async () => {
  const alice = await registerAndLogin('imga8');
  const bob = await registerAndLogin('imgb8');
  const outsider = await registerAndLogin('imgo8');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(outsider.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
    filename: 'photo.jpg',
    type: 'image',
  });

  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, 'CHAT_NOT_FOUND');
});

test('an image message is pushed live to the receiver as "message:new" (User A -> User B)', async () => {
  const alice = await registerAndLogin('imga9');
  const bob = await registerAndLogin('imgb9');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobReceives = waitForEvent(bobSocket, 'message:new');
    const sendRes = await sendMedia(alice.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
      filename: 'photo.jpg',
      type: 'image',
    });
    trackMediaUrl(sendRes);
    const pushed = await bobReceives;

    assert.equal(pushed.id, sendRes.body.message.id);
    assert.equal(pushed.type, 'image');
    assert.equal(pushed.mediaUrl, sendRes.body.message.mediaUrl);
  } finally {
    bobSocket.close();
  }
});

test('an image message from B is pushed live to A too (User B -> User A)', async () => {
  const alice = await registerAndLogin('imga10');
  const bob = await registerAndLogin('imgb10');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  try {
    const aliceReceives = waitForEvent(aliceSocket, 'message:new');
    const sendRes = await sendMedia(bob.accessToken, chatId, ENCRYPTED_IMAGE_BLOB, {
      filename: 'photo.png',
      type: 'image',
    });
    trackMediaUrl(sendRes);
    const pushed = await aliceReceives;

    assert.equal(pushed.id, sendRes.body.message.id);
    assert.equal(pushed.senderId, bob.id);
    assert.equal(pushed.type, 'image');
  } finally {
    aliceSocket.close();
  }
});

// --- Videos (encrypted) -------------------------------------------------

test('sending an encrypted video blob creates a video message with a stored mediaUrl', async () => {
  const alice = await registerAndLogin('vida1');
  const bob = await registerAndLogin('vidb1');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, ENCRYPTED_VIDEO_BLOB, {
    filename: 'clip.mp4',
    type: 'video',
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.message.type, 'video');
  assert.equal(res.body.message.body, null);
  assert.match(res.body.message.mediaUrl, /^\/uploads\/messages\/.+\.enc$/);
  trackMediaUrl(res);

  const staticRes = await request(app).get(res.body.message.mediaUrl);
  assert.equal(staticRes.status, 200);
  assert.ok(Buffer.from(staticRes.body).equals(ENCRYPTED_VIDEO_BLOB));
});

test('a video message is persisted and visible to the receiver', async () => {
  const alice = await registerAndLogin('vida3');
  const bob = await registerAndLogin('vidb3');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMedia(alice.accessToken, chatId, ENCRYPTED_VIDEO_BLOB, {
    filename: 'clip.mp4',
    type: 'video',
  });
  trackMediaUrl(sendRes);

  const bobList = await listMessages(bob.accessToken, chatId);
  assert.equal(bobList.body.messages.length, 1);
  assert.equal(bobList.body.messages[0].type, 'video');
  assert.equal(bobList.body.messages[0].mediaUrl, sendRes.body.message.mediaUrl);
});

test('rejects a video over the 20MB cap', async () => {
  const alice = await registerAndLogin('vida4');
  const bob = await registerAndLogin('vidb4');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, OVERSIZED_BLOB, {
    filename: 'huge.mp4',
    type: 'video',
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_TOO_LARGE');
});

test('a video message is pushed live in both directions (A -> B and B -> A)', async () => {
  const alice = await registerAndLogin('vida5');
  const bob = await registerAndLogin('vidb5');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobReceives = waitForEvent(bobSocket, 'message:new');
    const sendRes = await sendMedia(alice.accessToken, chatId, ENCRYPTED_VIDEO_BLOB, {
      filename: 'clip.mp4',
      type: 'video',
    });
    trackMediaUrl(sendRes);
    const pushedToBob = await bobReceives;
    assert.equal(pushedToBob.id, sendRes.body.message.id);
    assert.equal(pushedToBob.type, 'video');

    const aliceReceives = waitForEvent(aliceSocket, 'message:new');
    const replyRes = await sendMedia(bob.accessToken, chatId, ENCRYPTED_VIDEO_BLOB, {
      filename: 'reply.webm',
      type: 'video',
    });
    trackMediaUrl(replyRes);
    const pushedToAlice = await aliceReceives;
    assert.equal(pushedToAlice.id, replyRes.body.message.id);
    assert.equal(pushedToAlice.senderId, bob.id);
    assert.equal(pushedToAlice.type, 'video');
  } finally {
    aliceSocket.close();
    bobSocket.close();
  }
});

// --- Audio (encrypted) ---------------------------------------------------

test('sending an encrypted audio blob creates an audio message with a stored mediaUrl', async () => {
  const alice = await registerAndLogin('auda1');
  const bob = await registerAndLogin('audb1');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, ENCRYPTED_AUDIO_BLOB, {
    filename: 'voice.m4a',
    type: 'audio',
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.message.type, 'audio');
  assert.equal(res.body.message.body, null);
  assert.match(res.body.message.mediaUrl, /^\/uploads\/messages\/.+\.enc$/);
  trackMediaUrl(res);

  const staticRes = await request(app).get(res.body.message.mediaUrl);
  assert.equal(staticRes.status, 200);
  assert.ok(Buffer.from(staticRes.body).equals(ENCRYPTED_AUDIO_BLOB));
});

test('an audio message is persisted and visible to the receiver', async () => {
  const alice = await registerAndLogin('auda2');
  const bob = await registerAndLogin('audb2');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMedia(alice.accessToken, chatId, ENCRYPTED_AUDIO_BLOB, {
    filename: 'voice.m4a',
    type: 'audio',
  });
  trackMediaUrl(sendRes);

  const bobList = await listMessages(bob.accessToken, chatId);
  assert.equal(bobList.body.messages.length, 1);
  assert.equal(bobList.body.messages[0].type, 'audio');
  assert.equal(bobList.body.messages[0].mediaUrl, sendRes.body.message.mediaUrl);
});

test('rejects a voice recording over the 20MB cap', async () => {
  const alice = await registerAndLogin('auda3');
  const bob = await registerAndLogin('audb3');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMedia(alice.accessToken, chatId, OVERSIZED_BLOB, {
    filename: 'huge.m4a',
    type: 'audio',
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_TOO_LARGE');
});

test('an audio message is pushed live in both directions (A -> B and B -> A)', async () => {
  const alice = await registerAndLogin('auda4');
  const bob = await registerAndLogin('audb4');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobReceives = waitForEvent(bobSocket, 'message:new');
    const sendRes = await sendMedia(alice.accessToken, chatId, ENCRYPTED_AUDIO_BLOB, {
      filename: 'voice.m4a',
      type: 'audio',
    });
    trackMediaUrl(sendRes);
    const pushedToBob = await bobReceives;
    assert.equal(pushedToBob.id, sendRes.body.message.id);
    assert.equal(pushedToBob.type, 'audio');

    const aliceReceives = waitForEvent(aliceSocket, 'message:new');
    const replyRes = await sendMedia(bob.accessToken, chatId, ENCRYPTED_AUDIO_BLOB, {
      filename: 'reply.m4a',
      type: 'audio',
    });
    trackMediaUrl(replyRes);
    const pushedToAlice = await aliceReceives;
    assert.equal(pushedToAlice.id, replyRes.body.message.id);
    assert.equal(pushedToAlice.senderId, bob.id);
    assert.equal(pushedToAlice.type, 'audio');
  } finally {
    aliceSocket.close();
    bobSocket.close();
  }
});
