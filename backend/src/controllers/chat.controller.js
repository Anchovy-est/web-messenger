const chatService = require('../services/chat.service');
const invitationService = require('../services/invitation.service');
const pushService = require('../services/push.service');

async function list(req, res) {
  const archived = req.query.archived === 'true';
  const chats = await chatService.listChats(req.userId, archived);
  res.status(200).json({ chats });
}

async function createGroup(req, res) {
  const { chat, invitedUserIds } = await chatService.createGroupChat(req.userId, {
    name: req.body.name,
    participantIds: req.body.participantIds,
  });

  // Fire-and-forget, one per invitee — same reasoning as every other
  // push call in this app (invitation.controller.js `send`,
  // message.controller.js `notifyPush`): a push failure must never turn
  // an otherwise-successful group creation into a 500 response.
  for (const inviteeId of invitedUserIds) {
    pushService
      .notifyNewInvitation({ inviteeId, inviterId: req.userId, groupName: chat.name })
      .catch((err) => console.error('Push notification failed:', err));
  }

  res.status(201).json({ chat });
}

async function inviteToChat(req, res) {
  const invitation = await invitationService.inviteToChat(
    req.userId,
    req.params.id,
    req.body.inviteeId
  );

  pushService
    .notifyNewInvitation({
      inviteeId: req.body.inviteeId,
      inviterId: req.userId,
      groupName: invitation.chat.name,
    })
    .catch((err) => console.error('Push notification failed:', err));

  res.status(201).json({ invitation });
}

async function getOne(req, res) {
  const chat = await chatService.getChat(req.userId, req.params.id);
  res.status(200).json({ chat });
}

async function archive(req, res) {
  const chat = await chatService.archiveChat(req.userId, req.params.id);
  res.status(200).json({ chat });
}

async function unarchive(req, res) {
  const chat = await chatService.unarchiveChat(req.userId, req.params.id);
  res.status(200).json({ chat });
}

async function mute(req, res) {
  const chat = await chatService.muteChat(req.userId, req.params.id);
  res.status(200).json({ chat });
}

async function unmute(req, res) {
  const chat = await chatService.unmuteChat(req.userId, req.params.id);
  res.status(200).json({ chat });
}

module.exports = {
  list,
  createGroup,
  inviteToChat,
  getOne,
  archive,
  unarchive,
  mute,
  unmute,
};
