const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');

const chatService = require('./chat.service');
const messageModel = require('../models/message.model');
const pollModel = require('../models/poll.model');
const { ApiError } = require('../middleware/errorHandler');

const UPLOADS_ROOT = path.join(__dirname, '../../uploads');
const MEDIA_DIR = path.join(UPLOADS_ROOT, 'messages');

// Every operation here re-confirms membership through
// chatService.getChat first, which 404s the same way whether the
// chat doesn't exist or this user just isn't in it — a stranger can't
// probe for a chat's existence.
async function listMessages(userId, chatId, { limit, before } = {}) {
  await chatService.getChat(userId, chatId);
  const messages = await messageModel.listForChat(chatId, { limit, before });
  await attachPolls(messages, userId);
  // Fetching history also counts as delivery for this device — a
  // fallback for "was offline, opened the app later".
  const delivered = await messageModel.markReceipt(chatId, userId, { read: false });
  return { messages, delivered };
}

// Adds each poll-type message's `poll` (question, options, tally, own
// vote) — a poll's content lives in its own tables, not in
// messages.body. Deleted polls have nothing left to attach, so those
// are skipped.
async function attachPolls(messages, viewerUserId) {
  await Promise.all(
    messages
      .filter((message) => message.type === 'poll' && !message.deletedAt)
      .map(async (message) => {
        message.poll = await pollModel.findByMessageId(message.id, viewerUserId);
      })
  );
}

// `body` is an end-to-end-encrypted envelope from the client — this
// function and the database only ever see ciphertext.
async function sendMessage(userId, chatId, body) {
  await chatService.getChat(userId, chatId);
  return messageModel.createMessage({ chatId, senderId: userId, body });
}

// Image and video messages. The upload is already ciphertext by the
// time it gets here, so the server can't sniff its real content type
// — it trusts `declaredType`, validated by the schema. `wrappedKey`
// rides along in the same `body` column a text message uses; it's
// only present for group media, which has no shared chat key and so
// gets a fresh one-time key wrapped per recipient instead.
async function sendMediaMessage(userId, chatId, file, declaredType, wrappedKey) {
  await chatService.getChat(userId, chatId);

  await fs.mkdir(MEDIA_DIR, { recursive: true });
  const filename = `${chatId}-${Date.now()}-${crypto.randomUUID()}.enc`;
  await fs.writeFile(path.join(MEDIA_DIR, filename), file.buffer);

  return messageModel.createMessage({
    chatId,
    senderId: userId,
    type: declaredType,
    mediaUrl: `/uploads/messages/${filename}`,
    body: wrappedKey ?? null,
  });
}

async function markDelivered(userId, chatId) {
  await chatService.getChat(userId, chatId);
  return messageModel.markReceipt(chatId, userId, { read: false });
}

async function markRead(userId, chatId) {
  await chatService.getChat(userId, chatId);
  return messageModel.markReceipt(chatId, userId, { read: true });
}

// Being a participant lets you read every message, but not edit
// someone else's — that's a separate 403, not folded into getChat's
// 404, since there's nothing to hide here: the user can already see
// the message.
async function editMessage(userId, chatId, messageId, body) {
  await chatService.getChat(userId, chatId);

  const message = await messageModel.findById(messageId);
  if (!message || message.chatId !== chatId || message.deletedAt) {
    throw new ApiError(404, 'MESSAGE_NOT_FOUND', 'Message not found.');
  }
  if (message.senderId !== userId) {
    throw new ApiError(403, 'FORBIDDEN', 'You can only edit your own messages.');
  }

  return messageModel.updateMessageBody(messageId, body);
}

// Same authorization shape as editing — only the sender can delete,
// and an already-deleted message isn't a valid target.
async function deleteMessage(userId, chatId, messageId) {
  await chatService.getChat(userId, chatId);

  const message = await messageModel.findById(messageId);
  if (!message || message.chatId !== chatId || message.deletedAt) {
    throw new ApiError(404, 'MESSAGE_NOT_FOUND', 'Message not found.');
  }
  if (message.senderId !== userId) {
    throw new ApiError(403, 'FORBIDDEN', 'You can only delete your own messages.');
  }

  return messageModel.softDeleteMessage(messageId);
}

module.exports = {
  listMessages,
  sendMessage,
  sendMediaMessage,
  markDelivered,
  markRead,
  editMessage,
  deleteMessage,
};
