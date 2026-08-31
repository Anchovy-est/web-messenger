const messageService = require('../services/message.service');
const pushService = require('../services/push.service');
const { chatRoom } = require('../sockets');
const { ApiError } = require('../middleware/errorHandler');

// Fire-and-forget: a push failure must never turn an otherwise
// successful send into a 500 response.
function notifyPush(message) {
  pushService
    .notifyNewMessage({ chatId: message.chatId, senderId: message.senderId, type: message.type })
    .catch((err) => console.error('Push notification failed:', err));
}

// `io` is only set on `app` by server.js — absent in tests exercising
// createApp() directly. Broadcasting is a nice-to-have, not a
// precondition, so this degrades silently instead of failing.
function emitStatus(io, chatId, receipt) {
  if (io && receipt.messageIds.length > 0) {
    io.to(chatRoom(chatId)).emit('message:status', {
      chatId,
      messageIds: receipt.messageIds,
      status: receipt.status,
    });
  }
}

async function list(req, res) {
  const { limit, before } = req.query;
  const { messages, delivered } = await messageService.listMessages(req.userId, req.params.id, {
    limit,
    before,
  });
  emitStatus(req.app.get('io'), req.params.id, delivered);
  res.status(200).json({ messages });
}

async function send(req, res) {
  const message = await messageService.sendMessage(req.userId, req.params.id, req.body.body);

  const io = req.app.get('io');
  if (io) {
    io.to(chatRoom(req.params.id)).emit('message:new', message);
  }
  notifyPush(message);

  res.status(201).json({ message });
}

async function sendMedia(req, res) {
  if (!req.file) {
    throw new ApiError(400, 'FILE_REQUIRED', 'No file was uploaded.');
  }
  const message = await messageService.sendMediaMessage(
    req.userId,
    req.params.id,
    req.file,
    req.body.type,
    req.body.body
  );

  const io = req.app.get('io');
  if (io) {
    io.to(chatRoom(req.params.id)).emit('message:new', message);
  }
  notifyPush(message);

  res.status(201).json({ message });
}

async function markDelivered(req, res) {
  const receipt = await messageService.markDelivered(req.userId, req.params.id);
  emitStatus(req.app.get('io'), req.params.id, receipt);
  res.status(200).json({ messageIds: receipt.messageIds, status: receipt.status });
}

async function markRead(req, res) {
  const receipt = await messageService.markRead(req.userId, req.params.id);
  emitStatus(req.app.get('io'), req.params.id, receipt);
  res.status(200).json({ messageIds: receipt.messageIds, status: receipt.status });
}

async function edit(req, res) {
  const message = await messageService.editMessage(
    req.userId,
    req.params.id,
    req.params.messageId,
    req.body.body
  );

  const io = req.app.get('io');
  if (io) {
    io.to(chatRoom(req.params.id)).emit('message:edited', message);
  }

  res.status(200).json({ message });
}

async function deleteMessage(req, res) {
  const message = await messageService.deleteMessage(
    req.userId,
    req.params.id,
    req.params.messageId
  );

  const io = req.app.get('io');
  if (io) {
    io.to(chatRoom(req.params.id)).emit('message:deleted', message);
  }

  res.status(200).json({ message });
}

module.exports = { list, send, sendMedia, markDelivered, markRead, edit, deleteMessage };
