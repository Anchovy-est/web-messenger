const pollService = require('../services/poll.service');
const pushService = require('../services/push.service');
const { chatRoom } = require('../sockets');

// Fire-and-forget, same posture as message.controller.js `notifyPush` —
// a push failure must never turn an otherwise-successful request into a
// 500.
function notifyPush(message) {
  pushService
    .notifyNewMessage({ chatId: message.chatId, senderId: message.senderId, type: message.type })
    .catch((err) => console.error('Push notification failed:', err));
}

// A realtime `poll:updated` push is shared identically with everyone in
// the chat's room, unlike a REST response, which only ever goes back to
// the one caller who asked — so `myVoteOptionId` (this *viewer's* own
// current choice) is stripped before it goes out. Broadcasting it as-is
// would hand every other participant a snapshot of *whoever just voted's*
// own choice mislabeled as their own — at best confusing, at worst a
// real vote-identity leak on an anonymous poll. Each client already
// knows its own vote from the REST response the vote/retract call
// itself returned, and keeps that locally rather than trusting it to
// ever come from a broadcast.
function forBroadcast(poll) {
  const rest = { ...poll };
  delete rest.myVoteOptionId;
  return rest;
}

function broadcastPollUpdate(io, chatId, poll) {
  if (io) {
    io.to(chatRoom(chatId)).emit('poll:updated', { chatId, poll: forBroadcast(poll) });
  }
}

async function create(req, res) {
  const { message, poll } = await pollService.createPoll(req.userId, req.params.id, req.body);
  message.poll = poll;

  const io = req.app.get('io');
  if (io) {
    io.to(chatRoom(req.params.id)).emit('message:new', message);
  }
  notifyPush(message);

  res.status(201).json({ message, poll });
}

async function getOne(req, res) {
  const poll = await pollService.getPoll(req.userId, req.params.id, req.params.pollId);
  res.status(200).json({ poll });
}

async function vote(req, res) {
  const poll = await pollService.castVote(
    req.userId,
    req.params.id,
    req.params.pollId,
    req.body.optionId
  );
  broadcastPollUpdate(req.app.get('io'), req.params.id, poll);
  res.status(200).json({ poll });
}

async function retractVote(req, res) {
  const poll = await pollService.retractVote(req.userId, req.params.id, req.params.pollId);
  broadcastPollUpdate(req.app.get('io'), req.params.id, poll);
  res.status(200).json({ poll });
}

module.exports = { create, getOne, vote, retractVote };
