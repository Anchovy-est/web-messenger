/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // Same shape as archived_at (see …add-archived-at-to-chat-participants.js):
  // muting is per-user, per-chat, and a nullable timestamp rather than a
  // boolean so "when" is available for free — null means not muted.
  // Muting only suppresses *push notifications* for that chat; the chat
  // itself, its messages, and realtime socket delivery are unaffected —
  // a muted chat still updates live if it's open on screen.
  pgm.addColumn('chat_participants', {
    muted_at: { type: 'timestamptz' },
  });
};

exports.down = (pgm) => {
  pgm.dropColumn('chat_participants', 'muted_at');
};
