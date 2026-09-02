const invitationService = require('../services/invitation.service');

async function send(req, res) {
  const invitation = await invitationService.sendInvitation(req.userId, req.body.inviteeId);

  res.status(201).json({ invitation });
}

async function listReceived(req, res) {
  const invitations = await invitationService.listReceived(req.userId, req.query.status);
  res.status(200).json({ invitations });
}

async function listSent(req, res) {
  const invitations = await invitationService.listSent(req.userId, req.query.status);
  res.status(200).json({ invitations });
}

async function accept(req, res) {
  const invitation = await invitationService.acceptInvitation(req.userId, req.params.id);
  res.status(200).json({ invitation });
}

async function decline(req, res) {
  const invitation = await invitationService.declineInvitation(req.userId, req.params.id);
  res.status(200).json({ invitation });
}

module.exports = { send, listReceived, listSent, accept, decline };
