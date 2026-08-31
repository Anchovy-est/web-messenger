/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // One row per device, not per user — an account can be signed in on
  // several devices. `token` is globally unique, so a token that shows
  // up under a different account (logging out and back in as someone
  // else on the same phone) gets reassigned via ON CONFLICT.
  pgm.createTable('push_tokens', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    token: { type: 'text', notNull: true },
    // Not read anywhere yet, but useful once iOS support needs a
    // different FCM payload shape.
    platform: { type: 'text', notNull: true, default: 'android' },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  pgm.createIndex('push_tokens', 'token', { unique: true });
  pgm.createIndex('push_tokens', 'user_id');
};

exports.down = (pgm) => {
  pgm.dropTable('push_tokens');
};
