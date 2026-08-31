// Integration tests for push.service.js's decision logic (who gets
// notified, and whether a chat is muted) against a real Postgres
// connection.
//
// The actual Firebase call isn't under test — with no Firebase project
// configured, getMessaging() returns null and every send is a no-op,
// which is exactly what these tests confirm: missing credentials
// degrade to "does nothing", never a thrown error.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { createApp } = require('../app');
const { pool } = require('../config/db');
const pushService = require('./push.service');

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

function registerToken(accessToken, token) {
  return request(app)
    .put('/users/me/push-token')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ token });
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [createdUsernames]);
  }
  await pool.end();
});

test('recipientTokensForMessage returns the other participant\'s tokens, not the sender\'s', async () => {
  const alice = await registerAndLogin('pusha1');
  const bob = await registerAndLogin('pushb1');
  const chatId = await createAcceptedChat(alice, bob);
  await registerToken(alice.accessToken, 'alice-device-1');
  await registerToken(bob.accessToken, 'bob-device-1');

  const tokens = await pushService.recipientTokensForMessage(chatId, alice.id);

  assert.deepEqual(tokens, ['bob-device-1']);
});

test('recipientTokensForMessage returns all of the recipient\'s devices', async () => {
  const alice = await registerAndLogin('pusha2');
  const bob = await registerAndLogin('pushb2');
  const chatId = await createAcceptedChat(alice, bob);
  await registerToken(bob.accessToken, 'bob-phone');
  await registerToken(bob.accessToken, 'bob-tablet');

  const tokens = await pushService.recipientTokensForMessage(chatId, alice.id);

  assert.deepEqual(new Set(tokens), new Set(['bob-phone', 'bob-tablet']));
});

test('recipientTokensForMessage returns nothing once the recipient mutes the chat', async () => {
  const alice = await registerAndLogin('pusha3');
  const bob = await registerAndLogin('pushb3');
  const chatId = await createAcceptedChat(alice, bob);
  await registerToken(bob.accessToken, 'bob-device-3');

  await request(app).post(`/chats/${chatId}/mute`).set('Authorization', `Bearer ${bob.accessToken}`);

  const tokens = await pushService.recipientTokensForMessage(chatId, alice.id);

  assert.deepEqual(tokens, []);
});

test('recipientTokensForMessage resumes once the recipient unmutes the chat', async () => {
  const alice = await registerAndLogin('pusha4');
  const bob = await registerAndLogin('pushb4');
  const chatId = await createAcceptedChat(alice, bob);
  await registerToken(bob.accessToken, 'bob-device-4');
  await request(app).post(`/chats/${chatId}/mute`).set('Authorization', `Bearer ${bob.accessToken}`);

  await request(app)
    .post(`/chats/${chatId}/unmute`)
    .set('Authorization', `Bearer ${bob.accessToken}`);
  const tokens = await pushService.recipientTokensForMessage(chatId, alice.id);

  assert.deepEqual(tokens, ['bob-device-4']);
});

test('recipientTokensForMessage returns nothing if the recipient has no registered devices', async () => {
  const alice = await registerAndLogin('pusha5');
  const bob = await registerAndLogin('pushb5');
  const chatId = await createAcceptedChat(alice, bob);

  const tokens = await pushService.recipientTokensForMessage(chatId, alice.id);

  assert.deepEqual(tokens, []);
});

// A recipient muting their side of the chat must never affect the
// sender's experience — muting only suppresses the push to whoever
// muted it.
test('one participant muting a chat does not affect what the other would receive', async () => {
  const alice = await registerAndLogin('pusha6');
  const bob = await registerAndLogin('pushb6');
  const chatId = await createAcceptedChat(alice, bob);
  await registerToken(alice.accessToken, 'alice-device-6');
  await registerToken(bob.accessToken, 'bob-device-6');

  await request(app)
    .post(`/chats/${chatId}/mute`)
    .set('Authorization', `Bearer ${alice.accessToken}`);

  // Bob (unmuted) sending to Alice (muted): suppressed.
  assert.deepEqual(await pushService.recipientTokensForMessage(chatId, bob.id), []);
  // Alice (muted, but irrelevant to her own sends) sending to Bob
  // (unmuted): still delivered.
  assert.deepEqual(await pushService.recipientTokensForMessage(chatId, alice.id), [
    'bob-device-6',
  ]);
});

// --- Graceful degradation with no Firebase project configured -------------

test('notifyNewMessage does not throw when push notifications are not configured', async () => {
  const alice = await registerAndLogin('pusha7');
  const bob = await registerAndLogin('pushb7');
  const chatId = await createAcceptedChat(alice, bob);
  await registerToken(bob.accessToken, 'bob-device-7');

  await assert.doesNotReject(
    pushService.notifyNewMessage({ chatId, senderId: alice.id, type: 'text' })
  );
});

test('notifyNewInvitation does not throw when push notifications are not configured', async () => {
  const alice = await registerAndLogin('pusha8');
  const bob = await registerAndLogin('pushb8');
  await registerToken(bob.accessToken, 'bob-device-8');

  await assert.doesNotReject(
    pushService.notifyNewInvitation({ inviteeId: bob.id, inviterId: alice.id })
  );
});
