const chatModel = require('../models/chat.model');
const { ApiError } = require('../middleware/errorHandler');

async function listChats(userId, archived) {
  return chatModel.listForUser(userId, { archived });
}

async function getChat(userId, chatId) {
  const chat = await chatModel.findByIdForUser(chatId, userId);
  if (!chat) {
    // Same 404 whether the chat doesn't exist or the user just isn't in
    // it — distinguishing the two would confirm a chat id belongs to
    // someone else's conversation.
    throw new ApiError(404, 'CHAT_NOT_FOUND', 'Chat not found.');
  }
  return chat;
}

async function setArchived(userId, chatId, archived) {
  // Confirms membership first so a bad id gives 404, not a silent no-op.
  await getChat(userId, chatId);
  await chatModel.setArchived(chatId, userId, archived);
  return getChat(userId, chatId);
}

const archiveChat = (userId, chatId) => setArchived(userId, chatId, true);
const unarchiveChat = (userId, chatId) => setArchived(userId, chatId, false);

async function setMuted(userId, chatId, muted) {
  // Same reasoning as setArchived: confirm membership first so a bad id
  // gives 404, not a silent no-op.
  await getChat(userId, chatId);
  await chatModel.setMuted(chatId, userId, muted);
  return getChat(userId, chatId);
}

const muteChat = (userId, chatId) => setMuted(userId, chatId, true);
const unmuteChat = (userId, chatId) => setMuted(userId, chatId, false);

module.exports = {
  listChats,
  getChat,
  archiveChat,
  unarchiveChat,
  muteChat,
  unmuteChat,
};
