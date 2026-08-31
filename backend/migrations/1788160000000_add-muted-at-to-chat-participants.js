/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // Same shape as archived_at — per-user, per-chat, nullable timestamp.
  // Muting only suppresses push notifications; the chat still updates
  // live if it's open on screen.
  pgm.addColumn('chat_participants', {
    muted_at: { type: 'timestamptz' },
  });
};

exports.down = (pgm) => {
  pgm.dropColumn('chat_participants', 'muted_at');
};
