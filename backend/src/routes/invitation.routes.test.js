// Integration test for chat invitations against a real Postgres
// connection — see auth.routes.test.js for how to run this.
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

function send(token, inviteeId) {
  return request(app)
    .post('/invitations')
    .set('Authorization', `Bearer ${token}`)
    .send({ inviteeId });
}

function accept(token, invitationId) {
  return request(app)
    .post(`/invitations/${invitationId}/accept`)
    .set('Authorization', `Bearer ${token}`);
}

function decline(token, invitationId) {
  return request(app)
    .post(`/invitations/${invitationId}/decline`)
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

test('sending an invitation creates a pending invitation and adds the inviter to the chat', async () => {
  const alice = await registerAndLogin('inva1');
  const bob = await registerAndLogin('invb1');

  const res = await send(alice.accessToken, bob.id);

  assert.equal(res.status, 201);
  assert.equal(res.body.invitation.status, 'pending');
  assert.equal(res.body.invitation.inviter.id, alice.id);
  assert.equal(res.body.invitation.invitee.id, bob.id);

  const participants = await pool.query(
    'SELECT user_id FROM chat_participants WHERE chat_id = $1',
    [res.body.invitation.chatId]
  );
  assert.deepEqual(
    participants.rows.map((r) => r.user_id).sort(),
    [alice.id].sort()
  );
});

test('cannot invite yourself', async () => {
  const alice = await registerAndLogin('inva2');

  const res = await send(alice.accessToken, alice.id);

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'CANNOT_INVITE_SELF');
});

test('cannot invite a nonexistent user', async () => {
  const alice = await registerAndLogin('inva3');

  const res = await send(alice.accessToken, '00000000-0000-0000-0000-000000000000');

  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, 'USER_NOT_FOUND');
});

test('rejects a malformed inviteeId', async () => {
  const alice = await registerAndLogin('inva4');

  const res = await send(alice.accessToken, 'not-a-uuid');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('rejects a second invitation while one is already pending, in either direction', async () => {
  const alice = await registerAndLogin('inva5');
  const bob = await registerAndLogin('invb5');

  const first = await send(alice.accessToken, bob.id);
  assert.equal(first.status, 201);

  const sameDirection = await send(alice.accessToken, bob.id);
  assert.equal(sameDirection.status, 409);
  assert.equal(sameDirection.body.error.code, 'INVITATION_ALREADY_PENDING');

  const reverseDirection = await send(bob.accessToken, alice.id);
  assert.equal(reverseDirection.status, 409);
  assert.equal(reverseDirection.body.error.code, 'INVITATION_ALREADY_PENDING');
});

test('the invitee sees it in received, the inviter sees it in sent, and it does not leak to the wrong list',
  async () => {
    const alice = await registerAndLogin('inva6');
    const bob = await registerAndLogin('invb6');
    const invitation = (await send(alice.accessToken, bob.id)).body.invitation;

    const bobReceived = await request(app)
      .get('/invitations/received')
      .set('Authorization', `Bearer ${bob.accessToken}`);
    assert.ok(bobReceived.body.invitations.some((i) => i.id === invitation.id));

    const aliceSent = await request(app)
      .get('/invitations/sent')
      .set('Authorization', `Bearer ${alice.accessToken}`);
    assert.ok(aliceSent.body.invitations.some((i) => i.id === invitation.id));

    const aliceReceived = await request(app)
      .get('/invitations/received')
      .set('Authorization', `Bearer ${alice.accessToken}`);
    assert.deepEqual(aliceReceived.body.invitations, []);

    const bobSent = await request(app)
      .get('/invitations/sent')
      .set('Authorization', `Bearer ${bob.accessToken}`);
    assert.deepEqual(bobSent.body.invitations, []);
  });

test('the status filter on the listing endpoints works', async () => {
  const alice = await registerAndLogin('inva7');
  const bob = await registerAndLogin('invb7');
  const invitation = (await send(alice.accessToken, bob.id)).body.invitation;
  await decline(bob.accessToken, invitation.id);

  const pendingOnly = await request(app)
    .get('/invitations/sent?status=pending')
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.deepEqual(pendingOnly.body.invitations, []);

  const declinedOnly = await request(app)
    .get('/invitations/sent?status=declined')
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.ok(declinedOnly.body.invitations.some((i) => i.id === invitation.id));

  const badStatus = await request(app)
    .get('/invitations/sent?status=bogus')
    .set('Authorization', `Bearer ${alice.accessToken}`);
  assert.equal(badStatus.status, 400);
});

test('only the invitee can accept, and accepting adds them to the chat', async () => {
  const alice = await registerAndLogin('inva8');
  const bob = await registerAndLogin('invb8');
  const invitation = (await send(alice.accessToken, bob.id)).body.invitation;

  const wrongUser = await accept(alice.accessToken, invitation.id);
  assert.equal(wrongUser.status, 403);
  assert.equal(wrongUser.body.error.code, 'FORBIDDEN');

  const res = await accept(bob.accessToken, invitation.id);
  assert.equal(res.status, 200);
  assert.equal(res.body.invitation.status, 'accepted');

  const participants = await pool.query(
    'SELECT user_id FROM chat_participants WHERE chat_id = $1',
    [invitation.chatId]
  );
  assert.deepEqual(
    participants.rows.map((r) => r.user_id).sort(),
    [alice.id, bob.id].sort()
  );
});

test('cannot accept or decline an invitation that already has a response', async () => {
  const alice = await registerAndLogin('inva9');
  const bob = await registerAndLogin('invb9');
  const invitation = (await send(alice.accessToken, bob.id)).body.invitation;
  await accept(bob.accessToken, invitation.id);

  const acceptAgain = await accept(bob.accessToken, invitation.id);
  assert.equal(acceptAgain.status, 409);
  assert.equal(acceptAgain.body.error.code, 'INVITATION_NOT_PENDING');

  const declineAfterAccept = await decline(bob.accessToken, invitation.id);
  assert.equal(declineAfterAccept.status, 409);
});

test('declining leaves the inviter as the only participant, and does not create a chat connection',
  async () => {
    const alice = await registerAndLogin('inva10');
    const bob = await registerAndLogin('invb10');
    const invitation = (await send(alice.accessToken, bob.id)).body.invitation;

    const res = await decline(bob.accessToken, invitation.id);
    assert.equal(res.status, 200);
    assert.equal(res.body.invitation.status, 'declined');

    const participants = await pool.query(
      'SELECT user_id FROM chat_participants WHERE chat_id = $1',
      [invitation.chatId]
    );
    assert.deepEqual(
      participants.rows.map((r) => r.user_id),
      [alice.id]
    );
  });

test('a new invitation can be sent again after a decline', async () => {
  const alice = await registerAndLogin('inva11');
  const bob = await registerAndLogin('invb11');
  const first = (await send(alice.accessToken, bob.id)).body.invitation;
  await decline(bob.accessToken, first.id);

  const second = await send(alice.accessToken, bob.id);

  assert.equal(second.status, 201);
  assert.notEqual(second.body.invitation.id, first.id);
});

test('once two users share a chat, sending a new invitation is rejected — no invitation needed',
  async () => {
    const alice = await registerAndLogin('inva12');
    const bob = await registerAndLogin('invb12');
    const invitation = (await send(alice.accessToken, bob.id)).body.invitation;
    await accept(bob.accessToken, invitation.id);

    const res = await send(alice.accessToken, bob.id);

    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'ALREADY_IN_CHAT');
    assert.equal(res.body.error.details.chatId, invitation.chatId);

    // Symmetric: bob trying to invite alice hits the same rule.
    const reverse = await send(bob.accessToken, alice.id);
    assert.equal(reverse.status, 409);
    assert.equal(reverse.body.error.code, 'ALREADY_IN_CHAT');
  });

test('accepting or declining a nonexistent invitation returns 404', async () => {
  const alice = await registerAndLogin('inva13');

  const acceptRes = await accept(alice.accessToken, '00000000-0000-0000-0000-000000000000');
  assert.equal(acceptRes.status, 404);

  const declineRes = await decline(alice.accessToken, '00000000-0000-0000-0000-000000000000');
  assert.equal(declineRes.status, 404);
});

test('rejects a malformed invitation id', async () => {
  const alice = await registerAndLogin('inva14');

  const res = await accept(alice.accessToken, 'not-a-uuid');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('requires authentication for every endpoint', async () => {
  const sendRes = await request(app)
    .post('/invitations')
    .send({ inviteeId: '00000000-0000-0000-0000-000000000000' });
  assert.equal(sendRes.status, 401);

  const receivedRes = await request(app).get('/invitations/received');
  assert.equal(receivedRes.status, 401);

  const sentRes = await request(app).get('/invitations/sent');
  assert.equal(sentRes.status, 401);

  const acceptRes = await request(app).post(
    '/invitations/00000000-0000-0000-0000-000000000000/accept'
  );
  assert.equal(acceptRes.status, 401);
});
