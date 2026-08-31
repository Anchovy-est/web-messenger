const chatModel = require('../models/chat.model');
const userModel = require('../models/user.model');
const invitationModel = require('../models/invitation.model');
const { ApiError } = require('../middleware/errorHandler');

async function listChats(userId, archived) {
  return chatModel.listForUser(userId, { archived });
}

// Creates a group chat and immediately invites each selected user to
// it — mirrors invitation.service.js `sendInvitation`'s "the chat exists
// from the moment an invitation goes out" shape, just for potentially
// many invitees instead of exactly one: the creator is a participant
// immediately (see `chatModel.addParticipant` below), everyone else
// joins only once they accept their own invitation (through the
// existing POST /invitations/:id/accept endpoint — unchanged, since
// [respondToInvitation] never assumed a chat had exactly one other
// participant to begin with).
//
// Every invitee id is validated *before* the chat itself is created —
// failing partway through would otherwise leave a group chat behind
// with only some of the intended invitations actually sent, with no
// clean way for the creator to retry just the missing ones.
//
// Returns `{ chat, invitedUserIds }`, not just the chat — right after
// creation, none of the invitees are participants yet (they join only
// once they individually accept), so `chat.participants` is still just
// the creator; `invitedUserIds` is what a caller (chat.controller.js
// `createGroup`, for the initial push notifications) actually needs to
// know who to notify.
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
  createGroupChat,
  getChat,
  archiveChat,
  unarchiveChat,
  muteChat,
  unmuteChat,
};
