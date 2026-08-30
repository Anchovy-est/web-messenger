/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.createTable('chats', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    // Group chats have a name; 1:1 chats derive their display name from
    // the other participant client-side, so `name` stays null for those.
    is_group: { type: 'boolean', notNull: true, default: false },
    name: { type: 'text' },
    created_by: {
      type: 'uuid',
      references: 'users',
      onDelete: 'SET NULL',
    },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  pgm.createTable('chat_participants', {
    chat_id: {
      type: 'uuid',
      notNull: true,
      references: 'chats',
      onDelete: 'CASCADE',
    },
    user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    joined_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });
  pgm.addConstraint('chat_participants', 'chat_participants_pkey', {
    primaryKey: ['chat_id', 'user_id'],
  });
  // Reverse lookup: "which chats is this user in" (drives the chat list).
  pgm.createIndex('chat_participants', 'user_id');
};

exports.down = (pgm) => {
  pgm.dropTable('chat_participants');
  pgm.dropTable('chats');
};
