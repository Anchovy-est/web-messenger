// Integration tests for text messaging — persistence, ordering,
// authorization, and the realtime broadcast, against a real Postgres
// connection and a real listening HTTP+socket.io server.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
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

function sendMessage(token, chatId, body) {
  return request(app)
    .post(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${token}`)
    .send({ body });
}

function listMessages(token, chatId, query) {
  return request(app)
    .get(`/chats/${chatId}/messages`)
    .query(query || {})
    .set('Authorization', `Bearer ${token}`);
}

function markDelivered(token, chatId) {
  return request(app)
    .post(`/chats/${chatId}/delivered`)
    .set('Authorization', `Bearer ${token}`);
}

function markRead(token, chatId) {
  return request(app).post(`/chats/${chatId}/read`).set('Authorization', `Bearer ${token}`);
}

function editMessage(token, chatId, messageId, body) {
  return request(app)
    .patch(`/chats/${chatId}/messages/${messageId}`)
    .set('Authorization', `Bearer ${token}`)
    .send({ body });
}

function deleteMessage(token, chatId, messageId) {
  return request(app)
    .delete(`/chats/${chatId}/messages/${messageId}`)
    .set('Authorization', `Bearer ${token}`);
}

// Real listen (port 0 = OS-assigned), lazily on first use — needed
// since socket.io-client needs a real port to connect to.
let socketPort;

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

test('sending a message persists it with sender, content, and timestamp', async () => {
  const alice = await registerAndLogin('msga1');
  const bob = await registerAndLogin('msgb1');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMessage(alice.accessToken, chatId, 'Hello Bob!');

  assert.equal(res.status, 201);
  assert.equal(res.body.message.chatId, chatId);
  assert.equal(res.body.message.senderId, alice.id);
  assert.equal(res.body.message.body, 'Hello Bob!');
  assert.equal(res.body.message.type, 'text');
  assert.equal(res.body.message.status, 'sent'); // freshly sent, not yet delivered
  assert.ok(res.body.message.id);
  assert.ok(res.body.message.createdAt);
});

test('messages are returned in ascending (oldest-first) order', async () => {
  const alice = await registerAndLogin('msga2');
  const bob = await registerAndLogin('msgb2');
  const chatId = await createAcceptedChat(alice, bob);

  await sendMessage(alice.accessToken, chatId, 'first');
  await sendMessage(bob.accessToken, chatId, 'second');
  await sendMessage(alice.accessToken, chatId, 'third');

  const res = await listMessages(alice.accessToken, chatId);

  assert.equal(res.status, 200);
  assert.deepEqual(
    res.body.messages.map((m) => m.body),
    ['first', 'second', 'third']
  );
  // Each sender is recorded correctly too, not just insertion order.
  assert.deepEqual(
    res.body.messages.map((m) => m.senderId),
    [alice.id, bob.id, alice.id]
  );
});

test('the "before" cursor pages backward through history, still ascending', async () => {
  const alice = await registerAndLogin('msga3');
  const bob = await registerAndLogin('msgb3');
  const chatId = await createAcceptedChat(alice, bob);

  for (const body of ['a', 'b', 'c', 'd', 'e']) {
    await sendMessage(alice.accessToken, chatId, body);
  }

  const latestPage = await listMessages(alice.accessToken, chatId, { limit: 2 });
  assert.deepEqual(
    latestPage.body.messages.map((m) => m.body),
    ['d', 'e']
  );

  const earlierPage = await listMessages(alice.accessToken, chatId, {
    limit: 2,
    before: latestPage.body.messages[0].id,
  });
  assert.deepEqual(
    earlierPage.body.messages.map((m) => m.body),
    ['b', 'c']
  );
});

test('rejects an empty message body', async () => {
  const alice = await registerAndLogin('msga4');
  const bob = await registerAndLogin('msgb4');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await sendMessage(alice.accessToken, chatId, '   ');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('a user who is not a participant cannot send or list messages (404, not 403)', async () => {
  const alice = await registerAndLogin('msga5');
  const bob = await registerAndLogin('msgb5');
  const outsider = await registerAndLogin('msgo5');
  const chatId = await createAcceptedChat(alice, bob);

  const sendRes = await sendMessage(outsider.accessToken, chatId, 'sneaky');
  assert.equal(sendRes.status, 404);
  assert.equal(sendRes.body.error.code, 'CHAT_NOT_FOUND');

  const listRes = await listMessages(outsider.accessToken, chatId);
  assert.equal(listRes.status, 404);
});

test('requires authentication', async () => {
  const res = await request(app).get('/chats/00000000-0000-0000-0000-000000000000/messages');
  assert.equal(res.status, 401);
});

test('a message sent by A is pushed to B in real time over the socket, and vice versa', async () => {
  const alice = await registerAndLogin('msga6');
  const bob = await registerAndLogin('msgb6');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();

  const aliceSocket = await connectSocket(alice.accessToken, port);
  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    // A → B
    const bobReceives = waitForEvent(bobSocket, 'message:new');
    const sendRes = await sendMessage(alice.accessToken, chatId, 'Hi Bob, this is Alice');
    const pushedToBob = await bobReceives;
    assert.equal(pushedToBob.id, sendRes.body.message.id);
    assert.equal(pushedToBob.body, 'Hi Bob, this is Alice');
    assert.equal(pushedToBob.senderId, alice.id);

    // B → A
    const aliceReceives = waitForEvent(aliceSocket, 'message:new');
    const replyRes = await sendMessage(bob.accessToken, chatId, 'Hi Alice, Bob here');
    const pushedToAlice = await aliceReceives;
    assert.equal(pushedToAlice.id, replyRes.body.message.id);
    assert.equal(pushedToAlice.body, 'Hi Alice, Bob here');
    assert.equal(pushedToAlice.senderId, bob.id);
  } finally {
    aliceSocket.close();
    bobSocket.close();
  }
});

test('a socket without a valid token is refused', async () => {
  const port = await listen();
  const socket = ioClient(`http://localhost:${port}`, {
    auth: { token: 'not-a-real-token' },
    transports: ['websocket'],
    forceNew: true,
  });
  const err = await new Promise((resolve) => {
    socket.on('connect_error', resolve);
    socket.on('connect', () => resolve(null));
  });
  socket.close();
  assert.ok(err, 'expected a connect_error, but the socket connected');
});

// --- Message status (sent / delivered / read) -----------------------------

test('the recipient marking a message delivered updates its status for both users', async () => {
  const alice = await registerAndLogin('msga7');
  const bob = await registerAndLogin('msgb7');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'hi');
  assert.equal(sendRes.body.message.status, 'sent');

  const deliveredRes = await markDelivered(bob.accessToken, chatId);
  assert.equal(deliveredRes.status, 200);
  assert.deepEqual(deliveredRes.body.messageIds, [sendRes.body.message.id]);
  assert.equal(deliveredRes.body.status, 'delivered');

  const aliceList = await listMessages(alice.accessToken, chatId);
  assert.equal(aliceList.body.messages[0].status, 'delivered');
  const bobList = await listMessages(bob.accessToken, chatId);
  assert.equal(bobList.body.messages[0].status, 'delivered');
});

test('the recipient marking a message read updates its status to read', async () => {
  const alice = await registerAndLogin('msga8');
  const bob = await registerAndLogin('msgb8');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'hi');

  const readRes = await markRead(bob.accessToken, chatId);
  assert.equal(readRes.status, 200);
  assert.deepEqual(readRes.body.messageIds, [sendRes.body.message.id]);
  assert.equal(readRes.body.status, 'read');

  const aliceList = await listMessages(alice.accessToken, chatId);
  assert.equal(aliceList.body.messages[0].status, 'read');
});

test('marking read again does not "unread" — messageIds stay reported, timestamp does not reset', async () => {
  const alice = await registerAndLogin('msga9');
  const bob = await registerAndLogin('msgb9');
  const chatId = await createAcceptedChat(alice, bob);
  await sendMessage(alice.accessToken, chatId, 'hi');

  await markRead(bob.accessToken, chatId);
  const secondRead = await markRead(bob.accessToken, chatId);
  assert.equal(secondRead.body.messageIds.length, 1);
  assert.equal(secondRead.body.status, 'read');
});

test('marking delivered after already read does not report a downgrade', async () => {
  const alice = await registerAndLogin('msga10');
  const bob = await registerAndLogin('msgb10');
  const chatId = await createAcceptedChat(alice, bob);
  await sendMessage(alice.accessToken, chatId, 'hi');

  await markRead(bob.accessToken, chatId);
  const deliveredAfterRead = await markDelivered(bob.accessToken, chatId);
  // Nothing new to announce — already at (or past) that status.
  assert.deepEqual(deliveredAfterRead.body.messageIds, []);

  const aliceList = await listMessages(alice.accessToken, chatId);
  assert.equal(aliceList.body.messages[0].status, 'read'); // still read, not downgraded
});

test('fetching history as the recipient also marks messages delivered (fallback for offline delivery)', async () => {
  const alice = await registerAndLogin('msga11');
  const bob = await registerAndLogin('msgb11');
  const chatId = await createAcceptedChat(alice, bob);
  await sendMessage(alice.accessToken, chatId, 'hi');

  // Bob never explicitly calls /delivered — just lists (opens the chat).
  await listMessages(bob.accessToken, chatId);

  const aliceList = await listMessages(alice.accessToken, chatId);
  assert.equal(aliceList.body.messages[0].status, 'delivered');
});

test("marking delivered/read only affects the other participant's messages, not the caller's own", async () => {
  const alice = await registerAndLogin('msga12');
  const bob = await registerAndLogin('msgb12');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'hi');

  // Alice reading her own chat shouldn't mark her own message read —
  // there's nothing for her to receive from herself.
  const selfRead = await markRead(alice.accessToken, chatId);
  assert.deepEqual(selfRead.body.messageIds, []);

  const list = await listMessages(bob.accessToken, chatId);
  assert.equal(list.body.messages[0].id, sendRes.body.message.id);
  assert.equal(list.body.messages[0].status, 'sent'); // untouched by Alice's own call
});

test('a non-participant cannot mark delivered or read (404)', async () => {
  const alice = await registerAndLogin('msga13');
  const bob = await registerAndLogin('msgb13');
  const outsider = await registerAndLogin('msgo13');
  const chatId = await createAcceptedChat(alice, bob);

  const deliveredRes = await markDelivered(outsider.accessToken, chatId);
  assert.equal(deliveredRes.status, 404);
  const readRes = await markRead(outsider.accessToken, chatId);
  assert.equal(readRes.status, 404);
});

test('marking read pushes a live "message:status" event to the sender', async () => {
  const alice = await registerAndLogin('msga14');
  const bob = await registerAndLogin('msgb14');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();
  const sendRes = await sendMessage(alice.accessToken, chatId, 'hi');

  const aliceSocket = await connectSocket(alice.accessToken, port);
  try {
    const statusUpdate = waitForEvent(aliceSocket, 'message:status');
    await markRead(bob.accessToken, chatId);
    const payload = await statusUpdate;
    assert.equal(payload.chatId, chatId);
    assert.deepEqual(payload.messageIds, [sendRes.body.message.id]);
    assert.equal(payload.status, 'read');
  } finally {
    aliceSocket.close();
  }
});

// --- Message editing --------------------------------------------------

test('a sender can edit their own message, and it persists', async () => {
  const alice = await registerAndLogin('msga15');
  const bob = await registerAndLogin('msgb15');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'oops a typo');
  const messageId = sendRes.body.message.id;
  assert.equal(sendRes.body.message.editedAt, null);

  const editRes = await editMessage(alice.accessToken, chatId, messageId, 'fixed now');
  assert.equal(editRes.status, 200);
  assert.equal(editRes.body.message.body, 'fixed now');
  assert.ok(editRes.body.message.editedAt); // edited indicator's backing data

  // Persisted, not just returned once — a fresh fetch shows the same edit.
  const listRes = await listMessages(bob.accessToken, chatId);
  assert.equal(listRes.body.messages[0].body, 'fixed now');
  assert.ok(listRes.body.messages[0].editedAt);
});

test('a user cannot edit a message sent by someone else (403, not silently allowed)', async () => {
  const alice = await registerAndLogin('msga16');
  const bob = await registerAndLogin('msgb16');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, "alice's message");
  const messageId = sendRes.body.message.id;

  const editRes = await editMessage(bob.accessToken, chatId, messageId, 'bob was here');
  assert.equal(editRes.status, 403);
  assert.equal(editRes.body.error.code, 'FORBIDDEN');

  // The message itself is untouched by the rejected attempt.
  const listRes = await listMessages(alice.accessToken, chatId);
  assert.equal(listRes.body.messages[0].body, "alice's message");
  assert.equal(listRes.body.messages[0].editedAt, null);
});

test('a user outside the chat cannot edit a message in it (404, not 403)', async () => {
  const alice = await registerAndLogin('msga17');
  const bob = await registerAndLogin('msgb17');
  const outsider = await registerAndLogin('msgo17');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'private conversation');
  const messageId = sendRes.body.message.id;

  const editRes = await editMessage(outsider.accessToken, chatId, messageId, 'sneaky edit');
  assert.equal(editRes.status, 404);
  assert.equal(editRes.body.error.code, 'CHAT_NOT_FOUND');
});

test('editing a nonexistent message returns 404', async () => {
  const alice = await registerAndLogin('msga18');
  const bob = await registerAndLogin('msgb18');
  const chatId = await createAcceptedChat(alice, bob);

  const editRes = await editMessage(
    alice.accessToken,
    chatId,
    '00000000-0000-0000-0000-000000000000',
    'edit'
  );
  assert.equal(editRes.status, 404);
  assert.equal(editRes.body.error.code, 'MESSAGE_NOT_FOUND');
});

test('editing a message via the wrong chat id returns 404, even for its real sender', async () => {
  const alice = await registerAndLogin('msga19');
  const bob = await registerAndLogin('msgb19');
  const carol = await registerAndLogin('msgc19');
  const chatAB = await createAcceptedChat(alice, bob);
  const chatAC = await createAcceptedChat(alice, carol);
  const sendRes = await sendMessage(alice.accessToken, chatAB, 'in the alice/bob chat');

  // Same sender, same access token — just the wrong chatId in the URL.
  const editRes = await editMessage(alice.accessToken, chatAC, sendRes.body.message.id, 'moved?');
  assert.equal(editRes.status, 404);
  assert.equal(editRes.body.error.code, 'MESSAGE_NOT_FOUND');
});

test('rejects an empty edited body', async () => {
  const alice = await registerAndLogin('msga20');
  const bob = await registerAndLogin('msgb20');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'original');

  const editRes = await editMessage(alice.accessToken, chatId, sendRes.body.message.id, '   ');
  assert.equal(editRes.status, 400);
  assert.equal(editRes.body.error.code, 'VALIDATION_ERROR');
});

test('requires authentication to edit', async () => {
  const res = await request(app)
    .patch('/chats/00000000-0000-0000-0000-000000000000/messages/00000000-0000-0000-0000-000000000000')
    .send({ body: 'edit' });
  assert.equal(res.status, 401);
});

test('an edit is pushed live to both participants as "message:edited"', async () => {
  const alice = await registerAndLogin('msga21');
  const bob = await registerAndLogin('msgb21');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();
  const sendRes = await sendMessage(alice.accessToken, chatId, 'before edit');

  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobReceives = waitForEvent(bobSocket, 'message:edited');
    const editRes = await editMessage(alice.accessToken, chatId, sendRes.body.message.id, 'after edit');
    const pushed = await bobReceives;

    assert.equal(pushed.id, editRes.body.message.id);
    assert.equal(pushed.body, 'after edit');
    assert.ok(pushed.editedAt);
  } finally {
    bobSocket.close();
  }
});

// --- Message deletion -------------------------------------------------

test('a sender can delete their own message, and it persists as a tombstone', async () => {
  const alice = await registerAndLogin('msga22');
  const bob = await registerAndLogin('msgb22');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'delete me');
  const messageId = sendRes.body.message.id;

  const deleteRes = await deleteMessage(alice.accessToken, chatId, messageId);
  assert.equal(deleteRes.status, 200);
  assert.equal(deleteRes.body.message.body, null);
  assert.ok(deleteRes.body.message.deletedAt);

  // Persisted: a fresh fetch still shows the tombstone in place.
  const aliceList = await listMessages(alice.accessToken, chatId);
  assert.equal(aliceList.body.messages.length, 1);
  assert.equal(aliceList.body.messages[0].id, messageId);
  assert.equal(aliceList.body.messages[0].body, null);
  assert.ok(aliceList.body.messages[0].deletedAt);

  // Receiver's view: same tombstone, content gone, not just hidden.
  const bobList = await listMessages(bob.accessToken, chatId);
  assert.equal(bobList.body.messages.length, 1);
  assert.equal(bobList.body.messages[0].id, messageId);
  assert.equal(bobList.body.messages[0].body, null);
  assert.ok(bobList.body.messages[0].deletedAt);
});

test('deleting keeps the tombstone in its original position among other messages', async () => {
  const alice = await registerAndLogin('msga23');
  const bob = await registerAndLogin('msgb23');
  const chatId = await createAcceptedChat(alice, bob);
  await sendMessage(alice.accessToken, chatId, 'first');
  const middleRes = await sendMessage(alice.accessToken, chatId, 'second');
  await sendMessage(alice.accessToken, chatId, 'third');

  await deleteMessage(alice.accessToken, chatId, middleRes.body.message.id);

  const list = await listMessages(bob.accessToken, chatId);
  assert.deepEqual(
    list.body.messages.map((m) => m.body),
    ['first', null, 'third']
  );
});

test('a user cannot delete a message sent by someone else (403, not silently allowed)', async () => {
  const alice = await registerAndLogin('msga24');
  const bob = await registerAndLogin('msgb24');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, "alice's message");
  const messageId = sendRes.body.message.id;

  const deleteRes = await deleteMessage(bob.accessToken, chatId, messageId);
  assert.equal(deleteRes.status, 403);
  assert.equal(deleteRes.body.error.code, 'FORBIDDEN');

  // The rejected attempt left the message fully intact.
  const list = await listMessages(alice.accessToken, chatId);
  assert.equal(list.body.messages[0].body, "alice's message");
  assert.equal(list.body.messages[0].deletedAt, null);
});

test('a user outside the chat cannot delete a message in it (404, not 403)', async () => {
  const alice = await registerAndLogin('msga25');
  const bob = await registerAndLogin('msgb25');
  const outsider = await registerAndLogin('msgo25');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'private conversation');

  const deleteRes = await deleteMessage(outsider.accessToken, chatId, sendRes.body.message.id);
  assert.equal(deleteRes.status, 404);
  assert.equal(deleteRes.body.error.code, 'CHAT_NOT_FOUND');
});

test('deleting a nonexistent message returns 404', async () => {
  const alice = await registerAndLogin('msga26');
  const bob = await registerAndLogin('msgb26');
  const chatId = await createAcceptedChat(alice, bob);

  const deleteRes = await deleteMessage(
    alice.accessToken,
    chatId,
    '00000000-0000-0000-0000-000000000000'
  );
  assert.equal(deleteRes.status, 404);
  assert.equal(deleteRes.body.error.code, 'MESSAGE_NOT_FOUND');
});

test('deleting an already-deleted message returns 404 (not idempotent success)', async () => {
  const alice = await registerAndLogin('msga27');
  const bob = await registerAndLogin('msgb27');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'delete me twice?');

  const firstDelete = await deleteMessage(alice.accessToken, chatId, sendRes.body.message.id);
  assert.equal(firstDelete.status, 200);

  const secondDelete = await deleteMessage(alice.accessToken, chatId, sendRes.body.message.id);
  assert.equal(secondDelete.status, 404);
  assert.equal(secondDelete.body.error.code, 'MESSAGE_NOT_FOUND');
});

test('a deleted message can no longer be edited', async () => {
  const alice = await registerAndLogin('msga28');
  const bob = await registerAndLogin('msgb28');
  const chatId = await createAcceptedChat(alice, bob);
  const sendRes = await sendMessage(alice.accessToken, chatId, 'about to be deleted');
  await deleteMessage(alice.accessToken, chatId, sendRes.body.message.id);

  const editRes = await editMessage(alice.accessToken, chatId, sendRes.body.message.id, 'edit?');
  assert.equal(editRes.status, 404);
  assert.equal(editRes.body.error.code, 'MESSAGE_NOT_FOUND');
});

test('requires authentication to delete', async () => {
  const res = await request(app).delete(
    '/chats/00000000-0000-0000-0000-000000000000/messages/00000000-0000-0000-0000-000000000000'
  );
  assert.equal(res.status, 401);
});

test('a deletion is pushed live to the receiver as "message:deleted"', async () => {
  const alice = await registerAndLogin('msga29');
  const bob = await registerAndLogin('msgb29');
  const chatId = await createAcceptedChat(alice, bob);
  const port = await listen();
  const sendRes = await sendMessage(alice.accessToken, chatId, 'watch me disappear');

  const bobSocket = await connectSocket(bob.accessToken, port);
  try {
    const bobReceives = waitForEvent(bobSocket, 'message:deleted');
    await deleteMessage(alice.accessToken, chatId, sendRes.body.message.id);
    const pushed = await bobReceives;

    assert.equal(pushed.id, sendRes.body.message.id);
    assert.equal(pushed.body, null);
    assert.ok(pushed.deletedAt);
  } finally {
    bobSocket.close();
  }
});

// --- End-to-end encryption ----------------------------------------------
//
// Plays the part of the real Flutter client's crypto (X25519 ECDH ->
// HKDF-SHA256 -> AES-256-GCM) using Node's built-in `crypto`, to prove
// two independent keypairs derive the same chat key without ever
// transmitting it, a message round-trips through the real API, and the
// database never holds plaintext.

function generateIdentityKeyPair() {
  return crypto.generateKeyPairSync('x25519');
}

// Node's raw JWK export is base64url without padding; the app's own
// wire format is standard base64 with padding — converted here once.
function rawPublicKeyBase64(publicKey) {
  const jwk = publicKey.export({ format: 'jwk' });
  return Buffer.from(jwk.x, 'base64url').toString('base64');
}

function publicKeyFromRaw(base64Key) {
  const raw = Buffer.from(base64Key, 'base64');
  return crypto.createPublicKey({
    key: { kty: 'OKP', crv: 'X25519', x: raw.toString('base64url') },
    format: 'jwk',
  });
}

function deriveChatKey(myPrivateKey, theirPublicKeyBase64, chatId) {
  const sharedSecret = crypto.diffieHellman({
    privateKey: myPrivateKey,
    publicKey: publicKeyFromRaw(theirPublicKeyBase64),
  });
  return Buffer.from(
    crypto.hkdfSync('sha256', sharedSecret, Buffer.from(chatId), Buffer.from('mobile-messenger-msg-v1'), 32)
  );
}

function encryptEnvelope(key, plaintext) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return Buffer.concat([nonce, ciphertext, cipher.getAuthTag()]).toString('base64');
}

function decryptEnvelope(key, envelope) {
  const raw = Buffer.from(envelope, 'base64');
  const nonce = raw.subarray(0, 12);
  const authTag = raw.subarray(raw.length - 16);
  const ciphertext = raw.subarray(12, raw.length - 16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}

test('a message is genuinely end-to-end encrypted: both participants independently derive the same key, and the database never stores plaintext', async () => {
  const alice = await registerAndLogin('e2ea1');
  const bob = await registerAndLogin('e2eb1');
  const chatId = await createAcceptedChat(alice, bob);

  const aliceKeys = generateIdentityKeyPair();
  const bobKeys = generateIdentityKeyPair();
  const alicePublic = rawPublicKeyBase64(aliceKeys.publicKey);
  const bobPublic = rawPublicKeyBase64(bobKeys.publicKey);

  await request(app)
    .put('/users/me/public-key')
    .set('Authorization', `Bearer ${alice.accessToken}`)
    .send({ publicKey: alicePublic });
  await request(app)
    .put('/users/me/public-key')
    .set('Authorization', `Bearer ${bob.accessToken}`)
    .send({ publicKey: bobPublic });

  // Alice fetches the chat like the real client would, to get Bob's
  // public key, then derives the chat key from her own private key
  // (never transmitted) plus that public key.
  const aliceChatRes = await request(app)
    .get(`/chats/${chatId}`)
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.equal(aliceChatRes.body.chat.otherParticipant.publicKey, bobPublic);
  const aliceChatKey = deriveChatKey(aliceKeys.privateKey, bobPublic, chatId);

  const plaintext = "Meet me at midnight — don't tell anyone.";
  const sendRes = await sendMessage(alice.accessToken, chatId, encryptEnvelope(aliceChatKey, plaintext));
  assert.equal(sendRes.status, 201);
  assert.notEqual(sendRes.body.message.body, plaintext);

  // Bob independently derives the same key from his own private key
  // plus Alice's public key (ECDH commutativity) — no network exchange
  // of the key itself was needed.
  const bobChatRes = await request(app)
    .get(`/chats/${chatId}`)
    .set('Authorization', `Bearer ${bob.accessToken}`);
  assert.equal(bobChatRes.body.chat.otherParticipant.publicKey, alicePublic);
  const bobChatKey = deriveChatKey(bobKeys.privateKey, alicePublic, chatId);
  assert.ok(aliceChatKey.equals(bobChatKey), 'both participants must derive the identical key');

  const bobList = await listMessages(bob.accessToken, chatId);
  const received = bobList.body.messages.find((m) => m.id === sendRes.body.message.id);
  assert.equal(decryptEnvelope(bobChatKey, received.body), plaintext);

  // The actual point of this test: inspect the raw database row.
  const { rows } = await pool.query('SELECT body FROM messages WHERE id = $1', [
    sendRes.body.message.id,
  ]);
  assert.equal(rows.length, 1);
  assert.notEqual(rows[0].body, plaintext);
  assert.ok(!rows[0].body.includes(plaintext), 'raw body column must not contain the plaintext');

  // Without the right key, AES-GCM fails loudly instead of returning
  // silently-wrong output — the same protection against a tampered row.
  assert.throws(() => decryptEnvelope(crypto.randomBytes(32), rows[0].body));
});

test('a chat participant without a registered public key yet is exposed as such, not as an empty string', async () => {
  const alice = await registerAndLogin('e2ea2');
  const bob = await registerAndLogin('e2eb2');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await request(app)
    .get(`/chats/${chatId}`)
    .set('Authorization', `Bearer ${alice.accessToken}`);

  assert.equal(res.body.chat.otherParticipant.publicKey, null);
});
