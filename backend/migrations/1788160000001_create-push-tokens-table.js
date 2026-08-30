/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // One row per device, not per user — the same account can be signed in
  // on more than one device, and each gets its own push token. `token` is
  // globally unique (not just per-user): if the same device token turns
  // up under a different account (e.g. someone logs out and a different
  // person logs in on the same phone), the upsert in
  // pushToken.model.js `register` reassigns it via ON CONFLICT rather
  // than leaving two rows racing to own the same device.
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
    // Not read anywhere yet, but cheap to record now and genuinely useful
    // the moment iOS support (a different FCM payload shape) is added.
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
