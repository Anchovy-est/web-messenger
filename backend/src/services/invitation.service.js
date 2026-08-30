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
  acceptInvitation,
  declineInvitation,
  listReceived,
  listSent,
};
