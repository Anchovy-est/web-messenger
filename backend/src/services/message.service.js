const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');

const chatService = require('./chat.service');
const messageModel = require('../models/message.model');
const { ApiError } = require('../middleware/errorHandler');

const UPLOADS_ROOT = path.join(__dirname, '../../uploads');
const MEDIA_DIR = path.join(UPLOADS_ROOT, 'messages');

// All four operations start by re-confirming chat membership through
// chatService.getChat, which throws the same 404 whether the chat doesn't
// exist or this user just isn't in it (see chat.service.js) — a stranger
// can't probe for a chat's existence, and can't read, send, or mark
// receipts in a chat they were never invited to.
async function listMessages(userId, chatId, { limit, before } = {}) {
  await chatService.getChat(userId, chatId);
  const messages = await messageModel.listForChat(chatId, { limit, before });
  // Fetching history implies the requester's device now has whatever's
  // in it — a fallback delivery signal for "was offline, opened the app
  // later" that doesn't depend on the live socket ack the client also
  // sends on `message:new` (see message.controller.js `markDelivered`).
  const delivered = await messageModel.markReceipt(chatId, userId, { read: false });
  return { messages, delivered };
}

// `body` is an end-to-end-encrypted envelope the client produced (see
// lib/services/encryption_service.dart) — this function (and the
// database) only ever sees/stores that opaque ciphertext, never the
// plaintext message.
async function sendMessage(userId, chatId, body) {
  await chatService.getChat(userId, chatId);
  return messageModel.createMessage({ chatId, senderId: userId, body });
}

// Image and video messages. The client is expected to have already
// compressed the file to the 20MB cap before uploading (see the Flutter
// side) — this is the server's independent enforcement of that same cap
// (mediaUpload's multer `fileSize` limit, checked before this function
// even runs).
//
// The uploaded bytes are end-to-end-encrypted ciphertext (encrypted
// client-side, after compression, before upload), so magic-byte content
// sniffing isn't possible here — ciphertext has no meaningful magic
// bytes to detect, by design. `declaredType` (validated by
// schemas/message.schema.js to be
// `image` or `video`) is the only signal left; the server stores the
// ciphertext as-is under a generic extension and trusts the sender's own
// client to have encrypted the type it claims. This is a deliberate,
// unavoidable trade-off of true end-to-end encryption, not a regression:
// the server literally cannot inspect content it never has the key to
// decrypt.
async function sendMediaMessage(userId, chatId, file, declaredType) {
  await chatService.getChat(userId, chatId);

  await fs.mkdir(MEDIA_DIR, { recursive: true });
  const filename = `${chatId}-${Date.now()}-${crypto.randomUUID()}.enc`;
  await fs.writeFile(path.join(MEDIA_DIR, filename), file.buffer);

  return messageModel.createMessage({
    chatId,
    senderId: userId,
    type: declaredType,
    mediaUrl: `/uploads/messages/${filename}`,
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

// Editing. Membership alone (the `getChat` check every other
// operation here relies on) isn't enough authorization for a write that
// changes someone's own words — a chat participant can read every
// message in the chat, but must never be able to alter one they didn't
// write. That second check is deliberately a distinct 403 (not folded
// into the same 404 `getChat` throws for "not a participant"): a
// participant editing a chat-mate's message isn't probing for something
// that shouldn't be confirmed to exist — they can already see it — so
// there's nothing to protect by hiding *why* it's forbidden.
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

// Deletion. Same shape of authorization as editing (see its
// comment above) — a chat participant can see every message, but can
// only ever delete their own, and a message that's already deleted
// isn't a valid target for deleting again.
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
