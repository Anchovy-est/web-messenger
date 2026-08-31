const chatService = require('./chat.service');
const messageModel = require('../models/message.model');
const pollModel = require('../models/poll.model');
const { ApiError } = require('../middleware/errorHandler');

// Every operation starts by confirming chat membership through
// chatService.getChat, same as message.service.js.
async function createPoll(userId, chatId, { question, options, isAnonymous }) {
  const chat = await chatService.getChat(userId, chatId);
  if (!chat.isGroup) {
    // A poll is a group-chat feature — a 1:1 chat has no "who's still
    // undecided" question it answers that a plain message doesn't.
    throw new ApiError(400, 'NOT_A_GROUP_CHAT', 'Polls can only be created in group chats.');
  }

  // The poll rides along as its own message, like an image or video
  // — same send order, same realtime push. body/mediaUrl stay null;
  // the poll's real content lives in the polls/poll_options rows
  // created next.
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

// Casts a first vote, or changes an existing one — same DB operation
// either way (see poll.model.js). `optionId` is checked against this
// poll's own options first, so a request can't vote on some other
// poll's (or made-up) option id.
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
