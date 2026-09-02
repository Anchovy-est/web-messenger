const chatService = require('../services/chat.service');
const invitationService = require('../services/invitation.service');

async function list(req, res) {
  const archived = req.query.archived === 'true';
  const chats = await chatService.listChats(req.userId, archived);
  res.status(200).json({ chats });
}

async function createGroup(req, res) {
  const { chat } = await chatService.createGroupChat(req.userId, {
    name: req.body.name,
    participantIds: req.body.participantIds,
  });

  res.status(201).json({ chat });
}

async function inviteToChat(req, res) {
  const invitation = await invitationService.inviteToChat(
    req.userId,
    req.params.id,
    req.body.inviteeId
  );

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
