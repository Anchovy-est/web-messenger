// Integration test for the chat list against a real Postgres connection —
// see auth.routes.test.js for how to run this.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { createApp } = require('../app');
const { pool } = require('../config/db');

const app = createApp();

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

// Creates a real accepted chat between two users via the actual
// invitation flow, rather than inserting rows directly — exercises the
// same path a real user would.
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

function listChats(token, archived) {
  return request(app)
    .get('/chats')
    .query(archived === undefined ? {} : { archived })
    .set('Authorization', `Bearer ${token}`);
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

test('a fresh user has an empty chat list', async () => {
  const alice = await registerAndLogin('cla1');

  const res = await listChats(alice.accessToken);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.chats, []);
});

test('a chat does not appear until the invitation is accepted', async () => {
  const alice = await registerAndLogin('cla2');
  const bob = await registerAndLogin('clb2');

  await request(app)
    .post('/invitations')
    .set('Authorization', `Bearer ${alice.accessToken}`)
    .send({ inviteeId: bob.id });

  const aliceList = await listChats(alice.accessToken);
  assert.deepEqual(aliceList.body.chats, []);
  const bobList = await listChats(bob.accessToken);
  assert.deepEqual(bobList.body.chats, []);
});

test('once accepted, the chat appears for both users with the correct other participant', async () => {
  const alice = await registerAndLogin('cla3');
  const bob = await registerAndLogin('clb3');
  const chatId = await createAcceptedChat(alice, bob);

  const aliceList = await listChats(alice.accessToken);
  assert.equal(aliceList.body.chats.length, 1);
  assert.equal(aliceList.body.chats[0].id, chatId);
  assert.equal(aliceList.body.chats[0].otherParticipant.username, bob.username);

  const bobList = await listChats(bob.accessToken);
  assert.equal(bobList.body.chats.length, 1);
  assert.equal(bobList.body.chats[0].otherParticipant.username, alice.username);
});

test('chats are sorted by most recent activity, most recent first', async () => {
  const alice = await registerAndLogin('cla4');
  const bob = await registerAndLogin('clb4');
  const carol = await registerAndLogin('clc4');

  const olderChatId = await createAcceptedChat(alice, bob);
  const newerChatId = await createAcceptedChat(alice, carol);

  const res = await listChats(alice.accessToken);
  assert.deepEqual(
    res.body.chats.map((c) => c.id),
    [newerChatId, olderChatId]
  );

  // A new message on the older chat should bump it back to the top —
  // inserted directly here to isolate this test from the message-sending
  // endpoint's own behavior.
  await pool.query(
    `INSERT INTO messages (chat_id, sender_id, type, body) VALUES ($1, $2, 'text', 'hi')`,
    [olderChatId, bob.id]
  );

  const resAfter = await listChats(alice.accessToken);
  assert.deepEqual(
    resAfter.body.chats.map((c) => c.id),
    [olderChatId, newerChatId]
  );
  assert.equal(resAfter.body.chats[0].lastMessage.body, 'hi');
});

test('opening a chat you are part of returns its details', async () => {
  const alice = await registerAndLogin('cla5');
  const bob = await registerAndLogin('clb5');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await request(app)
    .get(`/chats/${chatId}`)
    .set('Authorization', `Bearer ${alice.accessToken}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.chat.id, chatId);
});

test('opening a chat you are not part of returns 404, not 403 (does not confirm it exists)', async () => {
  const alice = await registerAndLogin('cla6');
  const bob = await registerAndLogin('clb6');
  const outsider = await registerAndLogin('clo6');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await request(app)
    .get(`/chats/${chatId}`)
    .set('Authorization', `Bearer ${outsider.accessToken}`);

  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, 'CHAT_NOT_FOUND');
});

test('opening a nonexistent chat returns 404', async () => {
  const alice = await registerAndLogin('cla7');

  const res = await request(app)
    .get('/chats/00000000-0000-0000-0000-000000000000')
    .set('Authorization', `Bearer ${alice.accessToken}`);

  assert.equal(res.status, 404);
});

test('rejects a malformed chat id', async () => {
  const alice = await registerAndLogin('cla8');

  const res = await request(app)
    .get('/chats/not-a-uuid')
    .set('Authorization', `Bearer ${alice.accessToken}`);

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('archiving removes a chat from the default list and adds it to the archived list', async () => {
  const alice = await registerAndLogin('cla9');
  const bob = await registerAndLogin('clb9');
  const chatId = await createAcceptedChat(alice, bob);

  const archiveRes = await request(app)
    .post(`/chats/${chatId}/archive`)
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.equal(archiveRes.status, 200);
  assert.ok(archiveRes.body.chat.archivedAt);

  const activeList = await listChats(alice.accessToken);
  assert.deepEqual(activeList.body.chats, []);

  const archivedList = await listChats(alice.accessToken, 'true');
  assert.equal(archivedList.body.chats.length, 1);
  assert.equal(archivedList.body.chats[0].id, chatId);
});

test('archiving is per-user — the other participant is unaffected', async () => {
  const alice = await registerAndLogin('cla10');
  const bob = await registerAndLogin('clb10');
  const chatId = await createAcceptedChat(alice, bob);

  await request(app)
    .post(`/chats/${chatId}/archive`)
    .set('Authorization', `Bearer ${alice.accessToken}`);

  const bobList = await listChats(bob.accessToken);
  assert.equal(bobList.body.chats.length, 1);
  assert.equal(bobList.body.chats[0].archivedAt, null);
});

test('unarchiving restores a chat to the default list', async () => {
  const alice = await registerAndLogin('cla11');
  const bob = await registerAndLogin('clb11');
  const chatId = await createAcceptedChat(alice, bob);
  await request(app)
    .post(`/chats/${chatId}/archive`)
    .set('Authorization', `Bearer ${alice.accessToken}`);

  const unarchiveRes = await request(app)
    .post(`/chats/${chatId}/unarchive`)
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.equal(unarchiveRes.status, 200);
  assert.equal(unarchiveRes.body.chat.archivedAt, null);

  const activeList = await listChats(alice.accessToken);
  assert.equal(activeList.body.chats.length, 1);
});

test('archiving a chat you are not part of returns 404', async () => {
  const alice = await registerAndLogin('cla12');
  const bob = await registerAndLogin('clb12');
  const outsider = await registerAndLogin('clo12');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await request(app)
    .post(`/chats/${chatId}/archive`)
    .set('Authorization', `Bearer ${outsider.accessToken}`);

  assert.equal(res.status, 404);
});

test('rejects an invalid value for the archived filter', async () => {
  const alice = await registerAndLogin('cla13');

  const res = await listChats(alice.accessToken, 'not-a-boolean');

  assert.equal(res.status, 400);
});

test('requires authentication for every endpoint', async () => {
  const listRes = await request(app).get('/chats');
  assert.equal(listRes.status, 401);

  const getRes = await request(app).get('/chats/00000000-0000-0000-0000-000000000000');
  assert.equal(getRes.status, 401);

  const archiveRes = await request(app).post(
    '/chats/00000000-0000-0000-0000-000000000000/archive'
  );
  assert.equal(archiveRes.status, 401);
});

// --- Muting ---------------------------------------------------------------
//
// Same shape as archiving above, on purpose — mute/unmute is a distinct
// per-user preference from archive/unarchive (see
// backend/src/models/chat.model.js `setMuted`), but the endpoint
// contract is deliberately identical: 200 with the updated chat, 404 for
// a chat you're not in, per-user (not shared) effect.

test('muting a chat sets mutedAt, and the other participant is unaffected', async () => {
  const alice = await registerAndLogin('clm1');
  const bob = await registerAndLogin('clm2');
  const chatId = await createAcceptedChat(alice, bob);

  const muteRes = await request(app)
    .post(`/chats/${chatId}/mute`)
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.equal(muteRes.status, 200);
  assert.ok(muteRes.body.chat.mutedAt);

  const bobList = await listChats(bob.accessToken);
  assert.equal(bobList.body.chats[0].mutedAt, null);
});

test('unmuting restores a chat to not-muted', async () => {
  const alice = await registerAndLogin('clm3');
  const bob = await registerAndLogin('clm4');
  const chatId = await createAcceptedChat(alice, bob);
  await request(app)
    .post(`/chats/${chatId}/mute`)
    .set('Authorization', `Bearer ${alice.accessToken}`);

  const unmuteRes = await request(app)
    .post(`/chats/${chatId}/unmute`)
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.equal(unmuteRes.status, 200);
  assert.equal(unmuteRes.body.chat.mutedAt, null);
});

test('muting a chat you are not part of returns 404', async () => {
  const alice = await registerAndLogin('clm5');
  const bob = await registerAndLogin('clm6');
  const outsider = await registerAndLogin('clm7');
  const chatId = await createAcceptedChat(alice, bob);

  const res = await request(app)
    .post(`/chats/${chatId}/mute`)
    .set('Authorization', `Bearer ${outsider.accessToken}`);

  assert.equal(res.status, 404);
});

test('mute/unmute require authentication', async () => {
  const muteRes = await request(app).post(
    '/chats/00000000-0000-0000-0000-000000000000/mute'
  );
  assert.equal(muteRes.status, 401);

  const unmuteRes = await request(app).post(
    '/chats/00000000-0000-0000-0000-000000000000/unmute'
  );
  assert.equal(unmuteRes.status, 401);
});
