// Sends push notifications for new messages and invitations via
// Firebase Cloud Messaging. Every call here is fire-and-forget — a
// push failure is a degraded notification, never a reason to fail the
// request that triggered it.
//
// Message notification text is deliberately generic: `body`/`mediaUrl`
// are end-to-end encrypted and the server can't read them, so it can't
// say what a message contains — only its `type` (text/image/etc.),
// which is plaintext metadata.
const path = require('path');
const env = require('../config/env');
const chatModel = require('../models/chat.model');
const pushTokenModel = require('../models/pushToken.model');
const userModel = require('../models/user.model');

const MESSAGE_PREVIEW_BY_TYPE = {
  text: 'Sent you a message',
  image: 'Sent you a photo',
  video: 'Sent you a video',
  audio: 'Sent you a voice message',
  poll: 'Started a poll',
};

let messaging = null;
let initAttempted = false;

// Lazy, one-time init so firebase-admin is never required and no
// credentials are read in an environment without Firebase configured
// (every test run, most dev setups). Push is the one feature meant to
// silently do nothing when unconfigured, rather than error.
function getMessaging() {
  if (initAttempted) return messaging;
  initAttempted = true;

  if (!env.firebaseServiceAccountPath) {
    return null;
  }
  try {
    const admin = require('firebase-admin');
    const serviceAccount = require(path.resolve(env.firebaseServiceAccountPath));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    messaging = admin.messaging();
  } catch (err) {
    console.error('Firebase Admin failed to initialize; push notifications disabled.', err);
    messaging = null;
  }
  return messaging;
}

// Test-only hook: lets push.service.test.js reset the lazy-init guard
// between tests without a second process.
function _resetForTests() {
  messaging = null;
  initAttempted = false;
}

function isUnregisteredTokenError(err) {
  return (
    err?.code === 'messaging/registration-token-not-registered' ||
    err?.code === 'messaging/invalid-registration-token' ||
    err?.code === 'messaging/invalid-argument'
  );
}

async function sendToTokens(tokens, { title, body, data }) {
  const instance = getMessaging();
  if (!instance || tokens.length === 0) return;

  const results = await Promise.allSettled(
    tokens.map((token) =>
      instance.send({
        token,
        notification: { title, body },
        data,
      })
    )
  );

  // Clean up dead tokens now instead of retrying them forever.
  await Promise.all(
    results.map((result, i) => {
      if (result.status === 'rejected' && isUnregisteredTokenError(result.reason)) {
        return pushTokenModel.remove(tokens[i]);
      }
      return null;
    })
  );
}

// Kept separate from the FCM call above so it's testable against a
// real database without real Firebase credentials. Every other
// participant is a candidate, filtered independently by their own
// mute state — one person muting a group chat shouldn't affect
// anyone else's notifications.
async function recipientTokensForMessage(chatId, senderId) {
  const recipientIds = await chatModel.getOtherParticipantIds(chatId, senderId);
  const tokensPerRecipient = await Promise.all(
    recipientIds.map(async (recipientId) => {
      if (await chatModel.isMuted(chatId, recipientId)) return [];
      return pushTokenModel.listForUser(recipientId);
    })
  );
  return tokensPerRecipient.flat();
}

async function notifyNewMessage({ chatId, senderId, type }) {
  const tokens = await recipientTokensForMessage(chatId, senderId);
  if (tokens.length === 0) return;

  const sender = await userModel.findById(senderId);
  await sendToTokens(tokens, {
    title: sender ? sender.username : 'New message',
    body: MESSAGE_PREVIEW_BY_TYPE[type] || 'Sent you a message',
    data: { type: 'message', chatId },
  });
}

// `groupName` is only passed for a group invitation — its presence is
// what picks the notification text below.
async function notifyNewInvitation({ inviteeId, inviterId, groupName }) {
  const tokens = await pushTokenModel.listForUser(inviteeId);
  if (tokens.length === 0) return;

  const inviter = await userModel.findById(inviterId);
  let body = 'You have a new chat invitation.';
  if (inviter) {
    body = groupName
      ? `${inviter.username} invited you to "${groupName}".`
      : `${inviter.username} wants to chat with you.`;
  }
  await sendToTokens(tokens, {
    title: groupName ? 'New group invitation' : 'New chat invitation',
    body,
    data: { type: 'invitation' },
  });
}

module.exports = {
  notifyNewMessage,
  notifyNewInvitation,
  recipientTokensForMessage,
  _resetForTests,
};
