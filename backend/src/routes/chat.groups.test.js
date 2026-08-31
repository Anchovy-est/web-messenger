// Integration test for group chats — creation, invitations, membership
// permissions, and multi-recipient message status — against a real
// Postgres connection. See auth.routes.test.js for how to run this.
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

function createGroup(token, { name, participantIds }) {
  return request(app)
    .post('/chats/groups')
    .set('Authorization', `Bearer ${token}`)
    .send({ name, participantIds });
}

function inviteToChat(token, chatId, inviteeId) {
  return request(app)
    .post(`/chats/${chatId}/invitations`)
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

function receivedInvitations(token) {
  return request(app)
    .get('/invitations/received')
    .set('Authorization', `Bearer ${token}`);
}

function getChat(token, chatId) {
  return request(app).get(`/chats/${chatId}`).set('Authorization', `Bearer ${token}`);
}

function sendMessage(token, chatId, body) {
  return request(app)
    .post(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${token}`)
    .send({ body });
}

function markDelivered(token, chatId) {
  return request(app)
    .post(`/chats/${chatId}/delivered`)
    .set('Authorization', `Bearer ${token}`);
}

function markRead(token, chatId) {
  return request(app).post(`/chats/${chatId}/read`).set('Authorization', `Bearer ${token}`);
}

function listMessages(token, chatId) {
  return request(app)
    .get(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${token}`);
}

// Registers three users and gets a fully-formed 3-person group (creator
// + two accepted invitees) — the common starting point most tests below
// build on.
async function createThreePersonGroup(label) {
  const creator = await registerAndLogin(`${label}c`);
  const memberB = await registerAndLogin(`${label}b`);
  const memberC = await registerAndLogin(`${label}c2`);

  const createRes = await createGroup(creator.accessToken, {
    name: 'Weekend Trip',
    participantIds: [memberB.id, memberC.id],
  });
  const chatId = createRes.body.chat.id;

  const received = await receivedInvitations(memberB.accessToken);
  const invitationB = received.body.invitations.find((i) => i.chatId === chatId);
  await accept(memberB.accessToken, invitationB.id);

  const receivedC = await receivedInvitations(memberC.accessToken);
  const invitationC = receivedC.body.invitations.find((i) => i.chatId === chatId);
  await accept(memberC.accessToken, invitationC.id);

  return { creator, memberB, memberC, chatId };
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

test('creating a group chat names it, adds the creator, and invites every selected participant', async () => {
  const alice = await registerAndLogin('grpa1');
  const bob = await registerAndLogin('grpb1');
  const carol = await registerAndLogin('grpc1');

  const res = await createGroup(alice.accessToken, {
    name: 'Weekend Trip',
    participantIds: [bob.id, carol.id],
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.chat.isGroup, true);
  assert.equal(res.body.chat.name, 'Weekend Trip');
  assert.equal(res.body.chat.otherParticipant, null);

  const bobReceived = await receivedInvitations(bob.accessToken);
  const carolReceived = await receivedInvitations(carol.accessToken);
  assert.equal(
    bobReceived.body.invitations.some((i) => i.chatId === res.body.chat.id),
    true
  );
  assert.equal(
    carolReceived.body.invitations.some((i) => i.chatId === res.body.chat.id),
    true
  );
  // The invitation carries the group's own name/isGroup — this is what
  // lets a client show "Alice invited you to Weekend Trip" instead of a
  // generic "wants to chat" for a group invitation.
  const bobInvitation = bobReceived.body.invitations.find(
    (i) => i.chatId === res.body.chat.id
  );
  assert.equal(bobInvitation.chat.isGroup, true);
  assert.equal(bobInvitation.chat.name, 'Weekend Trip');
});

test('a group chat requires a name', async () => {
  const alice = await registerAndLogin('grpname1');
  const bob = await registerAndLogin('grpname2');

  const res = await createGroup(alice.accessToken, { name: '', participantIds: [bob.id] });

  assert.equal(res.status, 400);
});

test('a group chat requires at least one participant', async () => {
  const alice = await registerAndLogin('grppart1');

  const res = await createGroup(alice.accessToken, { name: 'Solo Group', participantIds: [] });

  assert.equal(res.status, 400);
});

test('inviting only yourself leaves no one to invite, and is rejected', async () => {
  const alice = await registerAndLogin('grpself1');

  const res = await createGroup(alice.accessToken, {
    name: 'Just Me',
    participantIds: [alice.id],
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'PARTICIPANTS_REQUIRED');
});

test('accepting a group invitation adds the member, and the group appears in their chat list', async () => {
  const { memberB, chatId } = await createThreePersonGroup('accgrp');

  const chatRes = await getChat(memberB.accessToken, chatId);
  assert.equal(chatRes.status, 200);
  assert.equal(chatRes.body.chat.isGroup, true);
  assert.equal(chatRes.body.chat.name, 'Weekend Trip');
});

test('declining a group invitation does not add the invitee as a participant', async () => {
  const alice = await registerAndLogin('grpdec1');
  const bob = await registerAndLogin('grpdec2');

  const createRes = await createGroup(alice.accessToken, {
    name: 'Declined Group',
    participantIds: [bob.id],
  });
  const chatId = createRes.body.chat.id;
  const received = await receivedInvitations(bob.accessToken);
  const invitation = received.body.invitations.find((i) => i.chatId === chatId);

  const declineRes = await decline(bob.accessToken, invitation.id);
  assert.equal(declineRes.status, 200);
  assert.equal(declineRes.body.invitation.status, 'declined');

  const chatRes = await getChat(bob.accessToken, chatId);
  assert.equal(chatRes.status, 404);
});

test('the chat payload lists every other participant of a group, but no single "otherParticipant"', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('listgrp');

  const res = await getChat(creator.accessToken, chatId);

  assert.equal(res.body.chat.otherParticipant, null);
  const participantIds = res.body.chat.participants.map((p) => p.id).sort();
  assert.deepEqual(participantIds, [memberB.id, memberC.id].sort());
});

test('an existing participant can invite one more person to the group', async () => {
  const { creator, chatId } = await createThreePersonGroup('addmore');
  const dave = await registerAndLogin('addmored');

  const res = await inviteToChat(creator.accessToken, chatId, dave.id);
  assert.equal(res.status, 201);
  assert.equal(res.body.invitation.chatId, chatId);

  const accepted = await accept(dave.accessToken, res.body.invitation.id);
  assert.equal(accepted.status, 200);
  const chatRes = await getChat(dave.accessToken, chatId);
  assert.equal(chatRes.status, 200);
});

test('someone who is not a participant cannot invite anyone to the group', async () => {
  const { chatId } = await createThreePersonGroup('notmember');
  const outsider = await registerAndLogin('notmembero');
  const target = await registerAndLogin('notmembert');

  const res = await inviteToChat(outsider.accessToken, chatId, target.id);

  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, 'CHAT_NOT_FOUND');
});

test('cannot invite someone who is already a participant of the group', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('already');

  const res = await inviteToChat(creator.accessToken, chatId, memberB.id);

  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, 'ALREADY_IN_CHAT');
});

test('cannot send a second pending invitation to the same person for the same group', async () => {
  const { creator, chatId } = await createThreePersonGroup('duppending');
  const dave = await registerAndLogin('duppendingd');

  const first = await inviteToChat(creator.accessToken, chatId, dave.id);
  assert.equal(first.status, 201);

  const second = await inviteToChat(creator.accessToken, chatId, dave.id);
  assert.equal(second.status, 409);
  assert.equal(second.body.error.code, 'INVITATION_ALREADY_PENDING');
});

test('inviting to a chat that is not a group is rejected', async () => {
  const alice = await registerAndLogin('notgroup1');
  const bob = await registerAndLogin('notgroup2');
  const carol = await registerAndLogin('notgroup3');

  const sendRes = await request(app)
    .post('/invitations')
    .set('Authorization', `Bearer ${alice.accessToken}`)
    .send({ inviteeId: bob.id });
  const invitationId = sendRes.body.invitation.id;
  await accept(bob.accessToken, invitationId);
  const directChatId = sendRes.body.invitation.chatId;

  const res = await inviteToChat(alice.accessToken, directChatId, carol.id);

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'NOT_A_GROUP_CHAT');
});

test('every member of a group can send and read messages in it', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('groupmsg');

  const sendRes = await sendMessage(creator.accessToken, chatId, 'hello group');
  assert.equal(sendRes.status, 201);

  const listB = await listMessages(memberB.accessToken, chatId);
  const listC = await listMessages(memberC.accessToken, chatId);
  assert.equal(listB.body.messages.some((m) => m.body === 'hello group'), true);
  assert.equal(listC.body.messages.some((m) => m.body === 'hello group'), true);
});

test('someone outside the group cannot read or send messages in it', async () => {
  const { chatId } = await createThreePersonGroup('groupmsgauth');
  const outsider = await registerAndLogin('groupmsgauthx');

  const listRes = await listMessages(outsider.accessToken, chatId);
  assert.equal(listRes.status, 404);

  const sendRes = await sendMessage(outsider.accessToken, chatId, 'sneaky');
  assert.equal(sendRes.status, 404);
});

test('a group message is only "delivered" once every other member has it, not just one', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('statusdeliv');

  const sendRes = await sendMessage(creator.accessToken, chatId, 'status check');
  const messageId = sendRes.body.message.id;
  assert.equal(sendRes.body.message.status, 'sent');

  // Only member B acks delivery — with three participants, the message
  // must NOT yet read as "delivered" for the group as a whole.
  await markDelivered(memberB.accessToken, chatId);
  const afterOne = await listMessages(creator.accessToken, chatId);
  const afterOneMsg = afterOne.body.messages.find((m) => m.id === messageId);
  assert.equal(afterOneMsg.status, 'sent');

  // Once member C also acks, every other participant has it — now it's
  // "delivered".
  await markDelivered(memberC.accessToken, chatId);
  const afterBoth = await listMessages(creator.accessToken, chatId);
  const afterBothMsg = afterBoth.body.messages.find((m) => m.id === messageId);
  assert.equal(afterBothMsg.status, 'delivered');
});

test('a group message is only "read" once every other member has read it', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('statusread');

  const sendRes = await sendMessage(creator.accessToken, chatId, 'read check');
  const messageId = sendRes.body.message.id;

  await markRead(memberB.accessToken, chatId);
  const afterOne = await listMessages(creator.accessToken, chatId);
  assert.equal(
    afterOne.body.messages.find((m) => m.id === messageId).status,
    // B has read it, but C hasn't even acked delivery yet — the message
    // isn't genuinely "delivered" (let alone "read") for the group as a
    // whole until every member has it, so this still reads "sent".
    'sent'
  );

  await markRead(memberC.accessToken, chatId);
  const afterBoth = await listMessages(creator.accessToken, chatId);
  assert.equal(afterBoth.body.messages.find((m) => m.id === messageId).status, 'read');
});

test('a 1:1 chat message status is unchanged by the group-aware aggregation (still just the one other participant)', async () => {
  const alice = await registerAndLogin('onetoone1');
  const bob = await registerAndLogin('onetoone2');

  const sendRes = await request(app)
    .post('/invitations')
    .set('Authorization', `Bearer ${alice.accessToken}`)
    .send({ inviteeId: bob.id });
  const chatId = sendRes.body.invitation.chatId;
  await accept(bob.accessToken, sendRes.body.invitation.id);

  const msgRes = await sendMessage(alice.accessToken, chatId, 'hi bob');
  const messageId = msgRes.body.message.id;

  await markDelivered(bob.accessToken, chatId);
  const afterDelivered = await listMessages(alice.accessToken, chatId);
  assert.equal(
    afterDelivered.body.messages.find((m) => m.id === messageId).status,
    'delivered'
  );

  await markRead(bob.accessToken, chatId);
  const afterRead = await listMessages(alice.accessToken, chatId);
  assert.equal(afterRead.body.messages.find((m) => m.id === messageId).status, 'read');
});
