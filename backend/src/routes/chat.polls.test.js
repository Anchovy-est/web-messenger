// Integration tests for group chat polls — creation, permission checks,
// voting/changing/retracting, anonymous-vs-public identity exposure,
// and realtime delivery. Runs a real HTTP+socket.io server since some
// tests need to observe a live push, not just the REST response.
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

function createGroup(token, { name, participantIds }) {
  return request(app)
    .post('/chats/groups')
    .set('Authorization', `Bearer ${token}`)
    .send({ name, participantIds });
}

function receivedInvitations(token) {
  return request(app)
    .get('/invitations/received')
    .set('Authorization', `Bearer ${token}`);
}

function accept(token, invitationId) {
  return request(app)
    .post(`/invitations/${invitationId}/accept`)
    .set('Authorization', `Bearer ${token}`);
}

// Registers three users into a fully-formed group (creator + two
// accepted invitees).
async function createThreePersonGroup(label) {
  const creator = await registerAndLogin(`${label}c`);
  const memberB = await registerAndLogin(`${label}b`);
  const memberC = await registerAndLogin(`${label}c2`);

  const createRes = await createGroup(creator.accessToken, {
    name: 'Trip Planning',
    participantIds: [memberB.id, memberC.id],
  });
  const chatId = createRes.body.chat.id;

  const receivedB = await receivedInvitations(memberB.accessToken);
  const invitationB = receivedB.body.invitations.find((i) => i.chatId === chatId);
  await accept(memberB.accessToken, invitationB.id);

  const receivedC = await receivedInvitations(memberC.accessToken);
  const invitationC = receivedC.body.invitations.find((i) => i.chatId === chatId);
  await accept(memberC.accessToken, invitationC.id);

  return { creator, memberB, memberC, chatId };
}

function createPoll(token, chatId, { question, options, isAnonymous }) {
  return request(app)
    .post(`/chats/${chatId}/polls`)
    .set('Authorization', `Bearer ${token}`)
    .send({ question, options, isAnonymous });
}

function getPoll(token, chatId, pollId) {
  return request(app)
    .get(`/chats/${chatId}/polls/${pollId}`)
    .set('Authorization', `Bearer ${token}`);
}

function castVote(token, chatId, pollId, optionId) {
  return request(app)
    .post(`/chats/${chatId}/polls/${pollId}/vote`)
    .set('Authorization', `Bearer ${token}`)
    .send({ optionId });
}

function retractVote(token, chatId, pollId) {
  return request(app)
    .delete(`/chats/${chatId}/polls/${pollId}/vote`)
    .set('Authorization', `Bearer ${token}`);
}

function listMessages(token, chatId) {
  return request(app)
    .get(`/chats/${chatId}/messages`)
    .set('Authorization', `Bearer ${token}`);
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
});

test('a group member can create a poll, which shows up as a message in the chat', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('create1');

  const res = await createPoll(creator.accessToken, chatId, {
    question: 'Where should we eat?',
    options: ['Pizza', 'Sushi', 'Tacos'],
  });

  assert.equal(res.status, 201);
  assert.equal(res.body.message.type, 'poll');
  assert.equal(res.body.message.chatId, chatId);
  assert.equal(res.body.poll.question, 'Where should we eat?');
  assert.equal(res.body.poll.isAnonymous, false);
  assert.equal(res.body.poll.options.length, 3);
  assert.deepEqual(
    res.body.poll.options.map((o) => o.text),
    ['Pizza', 'Sushi', 'Tacos']
  );
  assert.equal(
    res.body.poll.options.every((o) => o.voteCount === 0),
    true
  );
  assert.equal(res.body.poll.totalVotes, 0);

  // The poll is embedded in the message history for every other member,
  // not just the creator.
  const listRes = await listMessages(memberB.accessToken, chatId);
  const pollMessage = listRes.body.messages.find((m) => m.id === res.body.message.id);
  assert.ok(pollMessage);
  assert.equal(pollMessage.poll.question, 'Where should we eat?');
});

test('a poll requires at least 2 options', async () => {
  const { creator, chatId } = await createThreePersonGroup('opt1');

  const res = await createPoll(creator.accessToken, chatId, {
    question: 'Yes or no?',
    options: ['Only one'],
  });

  assert.equal(res.status, 400);
});

test('a poll rejects duplicate option text', async () => {
  const { creator, chatId } = await createThreePersonGroup('opt2');

  const res = await createPoll(creator.accessToken, chatId, {
    question: 'Pick one',
    options: ['Same', 'Same'],
  });

  assert.equal(res.status, 400);
});

test('polls cannot be created in a 1:1 chat', async () => {
  const alice = await registerAndLogin('nogrp1');
  const bob = await registerAndLogin('nogrp2');

  const sendRes = await request(app)
    .post('/invitations')
    .set('Authorization', `Bearer ${alice.accessToken}`)
    .send({ inviteeId: bob.id });
  const chatId = sendRes.body.invitation.chatId;
  await accept(bob.accessToken, sendRes.body.invitation.id);

  const res = await createPoll(alice.accessToken, chatId, {
    question: 'Pizza tonight?',
    options: ['Yes', 'No'],
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'NOT_A_GROUP_CHAT');
});

test('someone outside the group cannot create, view, or vote in its poll', async () => {
  const { creator, chatId } = await createThreePersonGroup('outsider1');
  const outsider = await registerAndLogin('outsider1x');

  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Board game night?',
    options: ['Yes', 'No'],
  });
  const pollId = createRes.body.poll.id;
  const optionId = createRes.body.poll.options[0].id;

  const outsiderCreate = await createPoll(outsider.accessToken, chatId, {
    question: 'Sneaky poll',
    options: ['A', 'B'],
  });
  assert.equal(outsiderCreate.status, 404);

  const outsiderGet = await getPoll(outsider.accessToken, chatId, pollId);
  assert.equal(outsiderGet.status, 404);

  const outsiderVote = await castVote(outsider.accessToken, chatId, pollId, optionId);
  assert.equal(outsiderVote.status, 404);
});

test('casting a vote is reflected in the tally and as "my vote" for that voter', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('vote1');

  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Movie night?',
    options: ['Yes', 'No'],
  });
  const pollId = createRes.body.poll.id;
  const yesOptionId = createRes.body.poll.options[0].id;

  const voteRes = await castVote(memberB.accessToken, chatId, pollId, yesOptionId);
  assert.equal(voteRes.status, 200);
  assert.equal(voteRes.body.poll.myVoteOptionId, yesOptionId);
  const yesOption = voteRes.body.poll.options.find((o) => o.id === yesOptionId);
  assert.equal(yesOption.voteCount, 1);
  assert.equal(voteRes.body.poll.totalVotes, 1);

  // Someone who hasn't voted sees the same tally, but no vote of
  // their own.
  const creatorView = await getPoll(creator.accessToken, chatId, pollId);
  assert.equal(creatorView.body.poll.myVoteOptionId, null);
  assert.equal(
    creatorView.body.poll.options.find((o) => o.id === yesOptionId).voteCount,
    1
  );
});

test('voting again for a different option changes the vote instead of adding a second one', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('vote2');

  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Best season?',
    options: ['Summer', 'Winter'],
  });
  const pollId = createRes.body.poll.id;
  const [summer, winter] = createRes.body.poll.options;

  await castVote(memberB.accessToken, chatId, pollId, summer.id);
  const changed = await castVote(memberB.accessToken, chatId, pollId, winter.id);

  assert.equal(changed.status, 200);
  assert.equal(changed.body.poll.myVoteOptionId, winter.id);
  assert.equal(changed.body.poll.options.find((o) => o.id === summer.id).voteCount, 0);
  assert.equal(changed.body.poll.options.find((o) => o.id === winter.id).voteCount, 1);
  // Still exactly one vote total, not two.
  assert.equal(changed.body.poll.totalVotes, 1);
});

test('retracting a vote removes it from the tally, and retracting again is a harmless no-op', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('retract1');

  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Pineapple on pizza?',
    options: ['Yes', 'No'],
  });
  const pollId = createRes.body.poll.id;
  const yesOptionId = createRes.body.poll.options[0].id;

  await castVote(memberB.accessToken, chatId, pollId, yesOptionId);
  const retracted = await retractVote(memberB.accessToken, chatId, pollId);

  assert.equal(retracted.status, 200);
  assert.equal(retracted.body.poll.myVoteOptionId, null);
  assert.equal(retracted.body.poll.totalVotes, 0);

  const retractedAgain = await retractVote(memberB.accessToken, chatId, pollId);
  assert.equal(retractedAgain.status, 200);
  assert.equal(retractedAgain.body.poll.totalVotes, 0);
});

test('voting for an option that does not belong to the poll is rejected', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('invalidopt1');

  const pollA = await createPoll(creator.accessToken, chatId, {
    question: 'Poll A',
    options: ['A1', 'A2'],
  });
  const pollB = await createPoll(creator.accessToken, chatId, {
    question: 'Poll B',
    options: ['B1', 'B2'],
  });
  const optionFromPollB = pollB.body.poll.options[0].id;

  const res = await castVote(memberB.accessToken, chatId, pollA.body.poll.id, optionFromPollB);
  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_OPTION');
});

test('a made-up option id is rejected the same way', async () => {
  const { creator, chatId } = await createThreePersonGroup('invalidopt2');

  const poll = await createPoll(creator.accessToken, chatId, {
    question: 'Poll',
    options: ['A', 'B'],
  });

  const res = await castVote(
    creator.accessToken,
    chatId,
    poll.body.poll.id,
    '00000000-0000-0000-0000-000000000000'
  );
  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_OPTION');
});

test('a public poll shows every participant who voted for each option', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('public1');

  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Coffee or tea?',
    options: ['Coffee', 'Tea'],
    isAnonymous: false,
  });
  const pollId = createRes.body.poll.id;
  const coffeeId = createRes.body.poll.options[0].id;

  await castVote(memberB.accessToken, chatId, pollId, coffeeId);
  await castVote(memberC.accessToken, chatId, pollId, coffeeId);

  const view = await getPoll(creator.accessToken, chatId, pollId);
  const coffee = view.body.poll.options.find((o) => o.id === coffeeId);
  const voterIds = coffee.voters.map((v) => v.id).sort();
  assert.deepEqual(voterIds, [memberB.id, memberC.id].sort());
  assert.equal(
    coffee.voters.every((v) => typeof v.username === 'string'),
    true
  );
});

test('an anonymous poll never exposes who voted for what, even to the creator or another participant', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('anon1');

  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Secret ballot: keep the office plant?',
    options: ['Yes', 'No'],
    isAnonymous: true,
  });
  const pollId = createRes.body.poll.id;
  const yesId = createRes.body.poll.options[0].id;

  await castVote(memberB.accessToken, chatId, pollId, yesId);
  const memberCVoteRes = await castVote(memberC.accessToken, chatId, pollId, yesId);

  // The tally is still visible...
  assert.equal(memberCVoteRes.body.poll.options.find((o) => o.id === yesId).voteCount, 2);
  // ...but nobody's individual identity is, for any viewer.
  for (const viewer of [creator, memberB, memberC]) {
    const view = await getPoll(viewer.accessToken, chatId, pollId);
    for (const option of view.body.poll.options) {
      assert.equal(Object.prototype.hasOwnProperty.call(option, 'voters'), false);
    }
  }
  // Each voter still sees their own vote back — not a leak, just
  // confirming their own choice.
  assert.equal(memberCVoteRes.body.poll.myVoteOptionId, yesId);
});

test('creating a poll broadcasts it in real time as a message:new event', async () => {
  const { creator, memberB, chatId } = await createThreePersonGroup('rtcreate1');
  const port = await listen();
  const bobSocket = await connectSocket(memberB.accessToken, port);

  try {
    const bobReceives = waitForEvent(bobSocket, 'message:new');
    const createRes = await createPoll(creator.accessToken, chatId, {
      question: 'Team lunch?',
      options: ['Yes', 'No'],
    });
    const payload = await bobReceives;

    assert.equal(payload.id, createRes.body.message.id);
    assert.equal(payload.type, 'poll');
    assert.equal(payload.poll.question, 'Team lunch?');
  } finally {
    bobSocket.close();
  }
});

test('casting a vote broadcasts the updated tally in real time, without leaking the voter\'s own choice as everyone else\'s', async () => {
  const { creator, memberB, memberC, chatId } = await createThreePersonGroup('rtvote1');
  const createRes = await createPoll(creator.accessToken, chatId, {
    question: 'Remote or office?',
    options: ['Remote', 'Office'],
  });
  const pollId = createRes.body.poll.id;
  const remoteId = createRes.body.poll.options[0].id;
  const port = await listen();
  const memberCSocket = await connectSocket(memberC.accessToken, port);

  try {
    const memberCReceives = waitForEvent(memberCSocket, 'poll:updated');
    await castVote(memberB.accessToken, chatId, pollId, remoteId);
    const payload = await memberCReceives;

    assert.equal(payload.chatId, chatId);
    assert.equal(payload.poll.id, pollId);
    assert.equal(payload.poll.options.find((o) => o.id === remoteId).voteCount, 1);
    // The broadcast is never personalized — this field must be absent
    // for every recipient.
    assert.equal(Object.prototype.hasOwnProperty.call(payload.poll, 'myVoteOptionId'), false);
  } finally {
    memberCSocket.close();
  }
});
