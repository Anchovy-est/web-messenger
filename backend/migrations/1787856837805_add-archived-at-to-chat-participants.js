/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // Archiving is per-user, per-chat — I archive a chat for myself; the
  // other participant's view of it is unaffected. Nullable timestamp
  // (not a boolean) so "when" is available for free if a future phase
  // wants it (e.g. sorting archived chats, or an "archived 3 days ago"
  // label) — null means not archived.
  pgm.addColumn('chat_participants', {
    archived_at: { type: 'timestamptz' },
  });
};

exports.down = (pgm) => {
  pgm.dropColumn('chat_participants', 'archived_at');
};
