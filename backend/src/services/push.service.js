// Sends push notifications for new messages and chat invitations via
// Firebase Cloud Messaging. Every call in this file is fire-and-forget
// from its caller's point of view (see message.controller.js /
// invitation.controller.js) — a push failure is a degraded notification
// experience, never a reason to fail the request that triggered it.
//
// Deliberately generic notification text for messages: `body`/`mediaUrl`
// are end-to-end encrypted (see docs/ENCRYPTION.md) and the server
// genuinely cannot read them, so "what does this message say" is not
// something a push notification here can ever show — the same
// constraint real E2EE messengers (Signal) operate under. `type`
// (text/image/video/audio) is plaintext metadata, not content, so it's
// fine to tailor the notification text to it.
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
};

let messaging = null;
let initAttempted = false;

// Lazily initialized (and only once) so `firebase-admin` — a fairly
// heavy dependency — is never even required, and no attempt is made to
// read credentials, in an environment that hasn't set up a Firebase
// project (every test run, and any dev environment before it's
// configured — see docs/PUSH_NOTIFICATIONS.md). Push notifications are
// the one feature in this app designed to degrade to "silently does
// nothing" rather than error when unconfigured, since unlike the JWT or
// encryption secrets, there's no way to fake a working substitute for
// real Firebase credentials in a test environment.
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
// between tests without needing a second process.
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

  // Dead tokens (uninstalled app, expired registration) are cheap to
  // clean up now rather than retried forever on every future message.
  await Promise.all(
    results.map((result, i) => {
      if (result.status === 'rejected' && isUnregisteredTokenError(result.reason)) {
        return pushTokenModel.remove(tokens[i]);
      }
      return null;
    })
  );
}

// The decision logic — who should be notified about a new message, and
// whether they've muted this chat — kept separate from the actual FCM
// call above so it's fully testable against a real database without
// needing real Firebase credentials (see push.service.test.js). Every
// *other* participant is a candidate — one for a 1:1 chat, however many
// for a group — each independently filtered by their own mute state,
// since one participant muting a group must never affect what anyone
// else in it receives.
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

// [groupName] is only ever passed for a group invitation (see
// invitation.controller.js) — its presence, not a separate `isGroup`
// flag, is what picks the notification text below, since there's
// nothing else to branch on that a caller could get out of sync.
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
