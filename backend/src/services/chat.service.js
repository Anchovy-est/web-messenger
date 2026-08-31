const chatModel = require('../models/chat.model');
const userModel = require('../models/user.model');
const invitationModel = require('../models/invitation.model');
const { ApiError } = require('../middleware/errorHandler');

async function listChats(userId, archived) {
  return chatModel.listForUser(userId, { archived });
}

// Creates a group chat and invites each selected user to it — the
// creator becomes a participant immediately, everyone else joins
// once they accept their own invitation via the existing accept
// endpoint.
//
// Every invitee is validated before the chat is created, so failing
// partway through doesn't leave a group chat with only some
// invitations sent.
//
// Returns { chat, invitedUserIds }, not just the chat — right after
// creation none of the invitees are participants yet, so
// chat.participants is still just the creator, and invitedUserIds is
// what the controller needs to send the initial push notifications.
async function createGroupChat(userId, { name, participantIds }) {
  const uniqueInviteeIds = [...new Set(participantIds)].filter((id) => id !== userId);
  if (uniqueInviteeIds.length === 0) {
    throw new ApiError(
      400,
      'PARTICIPANTS_REQUIRED',
      'Select at least one other participant.'
    );
  }

  for (const inviteeId of uniqueInviteeIds) {
    const invitee = await userModel.findById(inviteeId);
    if (!invitee) {
      throw new ApiError(404, 'USER_NOT_FOUND', 'One of the selected users was not found.');
    }
  }

  const chat = await chatModel.createChat({ isGroup: true, createdBy: userId, name });
  await chatModel.addParticipant(chat.id, userId);

  for (const inviteeId of uniqueInviteeIds) {
    await invitationModel.create({ chatId: chat.id, inviterId: userId, inviteeId });
  }

  return { chat: await getChat(userId, chat.id), invitedUserIds: uniqueInviteeIds };
}

async function getChat(userId, chatId) {
  const chat = await chatModel.findByIdForUser(chatId, userId);
  if (!chat) {
    // Same 404 whether the chat doesn't exist or the user isn't in it
    // — distinguishing them would confirm a chat id belongs to
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
  // Same reasoning as setArchived.
  await getChat(userId, chatId);
  await chatModel.setMuted(chatId, userId, muted);
  return getChat(userId, chatId);
}

const muteChat = (userId, chatId) => setMuted(userId, chatId, true);
const unmuteChat = (userId, chatId) => setMuted(userId, chatId, false);

module.exports = {
  listChats,
  createGroupChat,
  getChat,
  archiveChat,
  unarchiveChat,
  muteChat,
  unmuteChat,
};
