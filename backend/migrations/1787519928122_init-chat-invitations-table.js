/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // A chat is created up front (in a "pending" state, from the invitee's
  // point of view) when an invitation is sent; accepting it just flips
  // `status` and adds the invitee as a participant.
  pgm.createTable('chat_invitations', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    chat_id: {
      type: 'uuid',
      notNull: true,
      references: 'chats',
      onDelete: 'CASCADE',
    },
    inviter_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    invitee_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    status: {
      type: 'text',
      notNull: true,
      default: 'pending',
      check: "status IN ('pending', 'accepted', 'declined', 'cancelled')",
    },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
    responded_at: { type: 'timestamptz' },
  });

  pgm.createIndex('chat_invitations', 'invitee_id');
  pgm.createIndex('chat_invitations', 'inviter_id');
  // Prevent sending a second invite to the same person for the same chat
  // while one is still pending.
  pgm.createIndex('chat_invitations', ['chat_id', 'invitee_id'], {
    unique: true,
    where: "status = 'pending'",
    name: 'chat_invitations_pending_unique_idx',
  });
};

exports.down = (pgm) => {
  pgm.dropTable('chat_invitations');
};
