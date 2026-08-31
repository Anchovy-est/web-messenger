const userModel = require('../models/user.model');
const chatModel = require('../models/chat.model');
const invitationModel = require('../models/invitation.model');
const { ApiError } = require('../middleware/errorHandler');

async function sendInvitation(inviterId, inviteeId) {
  if (inviterId === inviteeId) {
    throw new ApiError(400, 'CANNOT_INVITE_SELF', 'You cannot invite yourself.');
  }

  const invitee = await userModel.findById(inviteeId);
  if (!invitee) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }

  // The requirement this app enforces: if you're already in a chat
  // together, no invitation is needed — send the client straight there
  // instead of letting them create a redundant one.
  const existingChat = await chatModel.findDirectChatBetween(inviterId, inviteeId);
  if (existingChat) {
    throw new ApiError(
      409,
      'ALREADY_IN_CHAT',
      'You already have a chat with this user.',
      { chatId: existingChat.id }
    );
  }

  const existingPending = await invitationModel.findPendingBetween(inviterId, inviteeId);
  if (existingPending) {
    throw new ApiError(
      409,
      'INVITATION_ALREADY_PENDING',
      'There is already a pending invitation between you and this user.',
      { invitationId: existingPending.id }
    );
  }

  // The chat exists from the moment the invitation is sent — the inviter
  // is a participant immediately; the invitee only joins on acceptance
  // (see migrations/…init-chat-invitations-table.js for the reasoning).
  const chat = await chatModel.createChat({ isGroup: false, createdBy: inviterId });
  await chatModel.addParticipant(chat.id, inviterId);

  return invitationModel.create({ chatId: chat.id, inviterId, inviteeId });
}

// Invites someone to an *existing* chat — used both by
// chat.service.js `createGroupChat` (inviting each initially-selected
// participant to the group chat it just created) and by the standalone
// "invite one more person" endpoint on an existing group. Deliberately a
// separate function from [sendInvitation] above rather than a shared
// one with branches: [sendInvitation] always creates a brand-new 1:1
// chat and enforces 1:1-only rules (at most one chat, at most one
// pending invitation, between any given pair of people); this enforces
// the group-appropriate versions of those same rules — scoped to *this*
// chat, since unlike a 1:1 relationship, the same two people can
// legitimately be in several different group chats together, or have
// more than one pending group invitation between them at once.
async function inviteToChat(inviterId, chatId, inviteeId) {
  if (inviterId === inviteeId) {
    throw new ApiError(400, 'CANNOT_INVITE_SELF', 'You cannot invite yourself.');
  }

  const chat = await chatModel.findByIdForUser(chatId, inviterId);
  if (!chat) {
    // Same 404-hides-existence reasoning as chat.service.js `getChat` —
    // a non-participant can't probe for a chat's existence by trying to
    // invite someone to it.
    throw new ApiError(404, 'CHAT_NOT_FOUND', 'Chat not found.');
  }
  if (!chat.isGroup) {
    throw new ApiError(
      400,
      'NOT_A_GROUP_CHAT',
      'This chat is not a group — start a new chat with an invitation instead.'
    );
  }

  const invitee = await userModel.findById(inviteeId);
  if (!invitee) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'User not found.');
  }

  if (await chatModel.isParticipant(chatId, inviteeId)) {
    throw new ApiError(409, 'ALREADY_IN_CHAT', 'This user is already in the group.');
  }

  const existingPending = await invitationModel.findPendingForChat(chatId, inviteeId);
  if (existingPending) {
    throw new ApiError(
      409,
      'INVITATION_ALREADY_PENDING',
      'There is already a pending invitation for this user.',
      { invitationId: existingPending.id }
    );
  }

  return invitationModel.create({ chatId, inviterId, inviteeId });
}

async function respondToInvitation(userId, invitationId, decision) {
  const invitation = await invitationModel.findById(invitationId);
  if (!invitation) {
    throw new ApiError(404, 'INVITATION_NOT_FOUND', 'Invitation not found.');
  }
  if (invitation.invitee.id !== userId) {
    throw new ApiError(
      403,
      'FORBIDDEN',
      'Only the invited user can respond to this invitation.'
    );
  }
  if (invitation.status !== 'pending') {
    throw new ApiError(
      409,
      'INVITATION_NOT_PENDING',
      `This invitation has already been ${invitation.status}.`
    );
  }

  if (decision === 'accepted') {
    await chatModel.addParticipant(invitation.chatId, userId);
  }

  return invitationModel.updateStatus(invitationId, decision);
}

const acceptInvitation = (userId, invitationId) =>
  respondToInvitation(userId, invitationId, 'accepted');

const declineInvitation = (userId, invitationId) =>
  respondToInvitation(userId, invitationId, 'declined');

async function listReceived(userId, status) {
  return invitationModel.listReceived(userId, { status });
}

async function listSent(userId, status) {
  return invitationModel.listSent(userId, { status });
}

module.exports = {
  sendInvitation,
  inviteToChat,
  acceptInvitation,
  declineInvitation,
  listReceived,
  listSent,
};
