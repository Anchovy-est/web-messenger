// Mobile and Web talk to the same API, so the server has no notion of
// "a mobile session" vs "a web session" — just a session. These tests
// confirm two simultaneous logins for the same account behave like two
// separate devices: separate tokens, separate sockets, shared data.
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

async function register(label) {
  const username = `test_${label}_${runId}`.slice(0, 20);
  createdUsernames.push(username);
  const credentials = {
    username,
    email: `test_${label}_${runId}@example.com`,
    password: 'Password123!',
  };
  await request(app).post('/auth/register').send(credentials);
  return credentials;
}

async function login(credentials) {
  const res = await request(app)
    .post('/auth/login')
    .send({ email: credentials.email, password: credentials.password });
  return {
    id: res.body.user.id,
    username: credentials.username,
    accessToken: res.body.accessToken,
    refreshToken: res.body.refreshToken,
  };
}

// One account, logged in twice — two separate POST /auth/login calls,
// like signing in on both the phone app and the browser: two unrelated
// refresh_tokens rows for the same user.
async function registerAndLoginTwice(label) {
  const credentials = await register(label);
  const mobile = await login(credentials);
  const web = await login(credentials);
  return { mobile, web, credentials };
}

async function registerAndLoginOnce(label) {
  return login(await register(label));
}

function me(session) {
  return request(app).get('/auth/me').set('Authorization', `Bearer ${session.accessToken}`);
}

function logout(session) {
  return request(app).post('/auth/logout').send({ refreshToken: session.refreshToken });
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

function sendMessage(session, chatId, body) {
  return request(app)
    .post(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${session.accessToken}`)
    .send({ body });
}

function editMessage(session, chatId, messageId, body) {
  return request(app)
    .patch(`/chats/${chatId}/messages/${messageId}`)
    .set('Authorization', `Bearer ${session.accessToken}`)
    .send({ body });
}

function deleteMessage(session, chatId, messageId) {
  return request(app)
    .delete(`/chats/${chatId}/messages/${messageId}`)
    .set('Authorization', `Bearer ${session.accessToken}`);
}

function markDelivered(session, chatId) {
  return request(app)
    .post(`/chats/${chatId}/delivered`)
    .set('Authorization', `Bearer ${session.accessToken}`);
}

function markRead(session, chatId) {
  return request(app)
    .post(`/chats/${chatId}/read`)
    .set('Authorization', `Bearer ${session.accessToken}`);
}

function listMessages(session, chatId) {
  return request(app)
    .get(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${session.accessToken}`);
}

let socketPort;
async function listen() {
  if (socketPort) return socketPort;
  await new Promise((resolve) => httpServer.listen(0, resolve));
  socketPort = httpServer.address().port;
  return socketPort;
}

function connectSocket(session, port) {
  const socket = ioClient(`http://localhost:${port}`, {
    auth: { token: session.accessToken },
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
});

test('Scenario A — logging in on Mobile and Web simultaneously keeps both sessions active', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenA');

  const [mobileMe, webMe] = await Promise.all([me(mobile), me(web)]);

  assert.equal(mobileMe.status, 200);
  assert.equal(webMe.status, 200);
  assert.equal(mobileMe.body.user.id, mobile.id);
  assert.equal(webMe.body.user.id, web.id);
  // Genuinely two sessions, not the same login handed back twice —
  // each has its own refresh token row. The short-lived access tokens
  // aren't compared: a JWT only encodes {sub, iat, exp}, so two logins
  // in the same second can produce byte-identical ones without sharing
  // a session.
  assert.notEqual(mobile.refreshToken, web.refreshToken);
});

test('Scenario B — a message sent from Mobile appears on Web in real time', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenB');
  const bob = await registerAndLoginOnce('scenBbob');
  const chatId = await createAcceptedChat(mobile, bob);
  const port = await listen();

  const webSocket = await connectSocket(web, port);
  try {
    const webReceives = waitForEvent(webSocket, 'message:new');
    const sendRes = await sendMessage(mobile, chatId, 'hello from mobile');
    assert.equal(sendRes.status, 201);

    const payload = await webReceives;
    assert.equal(payload.body, 'hello from mobile');
    assert.equal(payload.chatId, chatId);
  } finally {
    webSocket.close();
  }
});

test('Scenario C — a message sent from Web appears on Mobile in real time', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenC');
  const bob = await registerAndLoginOnce('scenCbob');
  const chatId = await createAcceptedChat(web, bob);
  const port = await listen();

  const mobileSocket = await connectSocket(mobile, port);
  try {
    const mobileReceives = waitForEvent(mobileSocket, 'message:new');
    const sendRes = await sendMessage(web, chatId, 'hello from web');
    assert.equal(sendRes.status, 201);

    const payload = await mobileReceives;
    assert.equal(payload.body, 'hello from web');
    assert.equal(payload.chatId, chatId);
  } finally {
    mobileSocket.close();
  }
});

test('Scenario D — editing and deleting a message syncs to every other session in real time', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenD');
  const bob = await registerAndLoginOnce('scenDbob');
  const chatId = await createAcceptedChat(mobile, bob);
  const port = await listen();

  const sendRes = await sendMessage(mobile, chatId, 'original text');
  const messageId = sendRes.body.message.id;

  const webSocket = await connectSocket(web, port);
  try {
    // Edit sent from Mobile — Web must see it live, and a fresh fetch
    // must reflect it too.
    const webSeesEdit = waitForEvent(webSocket, 'message:edited');
    const editRes = await editMessage(mobile, chatId, messageId, 'corrected text');
    assert.equal(editRes.status, 200);
    const editPayload = await webSeesEdit;
    assert.equal(editPayload.body, 'corrected text');
    assert.ok(editPayload.editedAt);

    const webListAfterEdit = await listMessages(web, chatId);
    assert.equal(
      webListAfterEdit.body.messages.find((m) => m.id === messageId).body,
      'corrected text'
    );

    // Delete, also sent from Mobile — same two checks.
    const webSeesDelete = waitForEvent(webSocket, 'message:deleted');
    const deleteRes = await deleteMessage(mobile, chatId, messageId);
    assert.equal(deleteRes.status, 200);
    const deletePayload = await webSeesDelete;
    assert.ok(deletePayload.deletedAt);
    assert.equal(deletePayload.body, null);

    const webListAfterDelete = await listMessages(web, chatId);
    const tombstone = webListAfterDelete.body.messages.find((m) => m.id === messageId);
    assert.ok(tombstone.deletedAt);
  } finally {
    webSocket.close();
  }
});

test('Scenario E — delivery and read state sync to every one of the sender\'s own sessions', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenE');
  const bob = await registerAndLoginOnce('scenEbob');
  const chatId = await createAcceptedChat(mobile, bob);
  const port = await listen();

  const sendRes = await sendMessage(mobile, chatId, 'did you get this?');
  const messageId = sendRes.body.message.id;
  assert.equal(sendRes.body.message.status, 'sent');

  // Both of the sender's own sessions are watching — a receipt from
  // bob should reach Mobile and Web, not just whichever one sent it.
  const mobileSocket = await connectSocket(mobile, port);
  const webSocket = await connectSocket(web, port);
  try {
    const mobileSeesDelivered = waitForEvent(mobileSocket, 'message:status');
    const webSeesDelivered = waitForEvent(webSocket, 'message:status');
    const deliveredRes = await markDelivered(bob, chatId);
    assert.equal(deliveredRes.status, 200);
    const [mobileDelivered, webDelivered] = await Promise.all([
      mobileSeesDelivered,
      webSeesDelivered,
    ]);
    assert.equal(mobileDelivered.status, 'delivered');
    assert.deepEqual(mobileDelivered.messageIds, [messageId]);
    assert.equal(webDelivered.status, 'delivered');

    const mobileSeesRead = waitForEvent(mobileSocket, 'message:status');
    const webSeesRead = waitForEvent(webSocket, 'message:status');
    await markRead(bob, chatId);
    const [mobileRead, webRead] = await Promise.all([mobileSeesRead, webSeesRead]);
    assert.equal(mobileRead.status, 'read');
    assert.equal(webRead.status, 'read');

    // And a plain re-fetch (no socket involved) agrees too.
    const refetched = await listMessages(mobile, chatId);
    assert.equal(refetched.body.messages.find((m) => m.id === messageId).status, 'read');
  } finally {
    mobileSocket.close();
    webSocket.close();
  }
});

test('Scenario F — logging out on Web leaves Mobile logged in', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenF');

  const logoutRes = await logout(web);
  assert.equal(logoutRes.status, 204);

  const mobileMe = await me(mobile);
  assert.equal(mobileMe.status, 200);
  const webMe = await me(web);
  // The access token is stateless, so it still decodes for a while
  // after logout — what logout actually revokes is the refresh token,
  // which is what matters once the access token expires. That's the
  // real assertion here, not webMe's status.
  assert.equal(webMe.status, 200);
  const refreshAfterLogout = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: web.refreshToken });
  assert.equal(refreshAfterLogout.status, 401);

  // Mobile's own refresh token is completely unaffected.
  const mobileRefresh = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: mobile.refreshToken });
  assert.equal(mobileRefresh.status, 200);
});

test('Scenario G — logging out on Mobile leaves Web logged in', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenG');

  const logoutRes = await logout(mobile);
  assert.equal(logoutRes.status, 204);

  const webMe = await me(web);
  assert.equal(webMe.status, 200);

  const mobileRefreshAfterLogout = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: mobile.refreshToken });
  assert.equal(mobileRefreshAfterLogout.status, 401);

  const webRefresh = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: web.refreshToken });
  assert.equal(webRefresh.status, 200);
});

test('Scenario H — data survives a full restart (every prior session logged out, then a completely fresh login re-fetches identical history)', async () => {
  const { mobile, web, credentials } = await registerAndLoginTwice('scenH');
  const bob = await registerAndLoginOnce('scenHbob');
  const chatId = await createAcceptedChat(mobile, bob);

  await sendMessage(mobile, chatId, 'kept across a restart');
  const second = await sendMessage(web, chatId, 'edited across a restart');
  await editMessage(web, chatId, second.body.message.id, 'edited across a restart (v2)');
  const third = await sendMessage(mobile, chatId, 'deleted across a restart');
  await deleteMessage(mobile, chatId, third.body.message.id);

  // Every session this test opened is logged out — the same state as
  // the app being killed and relaunched. Only a fresh login gets back in.
  await Promise.all([logout(mobile), logout(web), logout(bob)]);
  const restarted = await login(credentials);

  const history = await listMessages(restarted, chatId);
  assert.equal(history.status, 200);
  const byBody = (text) => history.body.messages.find((m) => m.body === text);
  assert.ok(byBody('kept across a restart'));
  assert.ok(byBody('edited across a restart (v2)'));
  assert.equal(byBody('edited across a restart'), undefined); // superseded by the edit
  const deletedTombstone = history.body.messages.find(
    (m) => m.id === third.body.message.id
  );
  assert.ok(deletedTombstone.deletedAt);
  assert.equal(deletedTombstone.body, null);
});

// Measures send-to-receive latency directly, isolated from the
// registration/login/invitation setup the scenario tests above also
// time. "Normal conditions" here means loopback to a local backend —
// a real deployed network path would have different latency.
test('message delivery latency is well under the 2-second target under normal (local) conditions', async () => {
  const { mobile, web } = await registerAndLoginTwice('scenLatency');
  const bob = await registerAndLoginOnce('scenLatencybob');
  const chatId = await createAcceptedChat(mobile, bob);
  const port = await listen();

  const webSocket = await connectSocket(web, port);
  try {
    const startedAt = Date.now();
    const webReceives = waitForEvent(webSocket, 'message:new');
    await sendMessage(mobile, chatId, 'timing check');
    await webReceives;
    const elapsedMs = Date.now() - startedAt;

    console.log(`Measured send-to-receive latency: ${elapsedMs}ms`);
    assert.ok(
      elapsedMs < 2000,
      `expected delivery under 2000ms, took ${elapsedMs}ms`
    );
  } finally {
    webSocket.close();
  }
});
