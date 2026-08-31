/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // type/media_url are here from the start so image/video/audio reuse
  // this table without a migration per media type; edited_at/deleted_at
  // likewise so editing and soft-delete need no later ALTER TABLE.
  pgm.createTable('messages', {
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
    sender_id: {
      type: 'uuid',
      references: 'users',
      onDelete: 'SET NULL',
    },
    type: {
      type: 'text',
      notNull: true,
      default: 'text',
      check: "type IN ('text', 'image', 'video', 'audio')",
    },
    body: { type: 'text' },
    media_url: { type: 'text' },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
    edited_at: { type: 'timestamptz' },
    deleted_at: { type: 'timestamptz' },
  });

  // Message list pagination: "latest N messages in this chat".
  pgm.createIndex('messages', ['chat_id', 'created_at']);

  // Per-recipient delivery/read state, keyed by (message, user) so
  // group chats can show "read by 2 of 4" instead of one shared marker.
  pgm.createTable('message_receipts', {
    message_id: {
      type: 'uuid',
      notNull: true,
      references: 'messages',
      onDelete: 'CASCADE',
    },
    user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    delivered_at: { type: 'timestamptz' },
    read_at: { type: 'timestamptz' },
  });
  pgm.addConstraint('message_receipts', 'message_receipts_pkey', {
    primaryKey: ['message_id', 'user_id'],
  });
};

exports.down = (pgm) => {
  pgm.dropTable('message_receipts');
  pgm.dropTable('messages');
};
