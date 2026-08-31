const chatService = require('./chat.service');
const messageModel = require('../models/message.model');
const pollModel = require('../models/poll.model');
const { ApiError } = require('../middleware/errorHandler');

// Every operation starts by re-confirming chat membership through
// chatService.getChat, same as message.service.js — a stranger gets the
// same 404 whether the chat doesn't exist or they're just not in it, and
// can't create, view, or vote in a poll for a chat they were never
// invited to.
async function createPoll(userId, chatId, { question, options, isAnonymous }) {
  const chat = await chatService.getChat(userId, chatId);
  if (!chat.isGroup) {
    // Matches invitation.service.js `inviteToChat`'s same restriction —
    // a poll is a group-chat feature; a 1:1 chat has no "who's still
    // undecided" question a poll answers that a plain message doesn't
    // already.
    throw new ApiError(400, 'NOT_A_GROUP_CHAT', 'Polls can only be created in group chats.');
  }

  // The poll rides along as its own message, exactly like an image or
  // video does — it shows up in the thread in send order, gets the same
  // realtime `message:new` push, and needs no bespoke "where does this
  // render" logic client-side. `body`/`mediaUrl` are left null: a poll's
  // actual content lives in the `polls`/`poll_options` rows this
  // function creates next, not in the messages table.
  const message = await messageModel.createMessage({ chatId, senderId: userId, type: 'poll' });
  const poll = await pollModel.createPoll({
    messageId: message.id,
    chatId,
    creatorId: userId,
    question,
    options,
    isAnonymous,
  });
  return { message, poll };
}

async function getPoll(userId, chatId, pollId) {
  await chatService.getChat(userId, chatId);
  const poll = await pollModel.findById(pollId, userId);
  if (!poll || poll.chatId !== chatId) {
    throw new ApiError(404, 'POLL_NOT_FOUND', 'Poll not found.');
  }
  return poll;
}

// Casts a first vote, or changes an existing one — see poll.model.js
// `vote`'s doc comment for why those are the same database operation.
// `optionId` is checked against this specific poll's own options first:
// without that, nothing would stop a request naming some *other* poll's
// (or an outright made-up) option id from recording a "vote" that
// doesn't correspond to anything this poll actually offers.
async function castVote(userId, chatId, pollId, optionId) {
  const poll = await getPoll(userId, chatId, pollId);
  const isValidOption = poll.options.some((option) => option.id === optionId);
  if (!isValidOption) {
    throw new ApiError(400, 'INVALID_OPTION', 'That option does not belong to this poll.');
  }

  await pollModel.vote(pollId, optionId, userId);
  return pollModel.findById(pollId, userId);
}

async function retractVote(userId, chatId, pollId) {
  await getPoll(userId, chatId, pollId); // membership + existence check
  await pollModel.retractVote(pollId, userId);
  return pollModel.findById(pollId, userId);
}

module.exports = { createPoll, getPoll, castVote, retractVote };
