/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // gen_random_uuid() lives in pgcrypto on PG < 16; enabling it explicitly
  // keeps this migration portable regardless of which PG version runs it.
  pgm.createExtension('pgcrypto', { ifNotExists: true });

  pgm.createTable('users', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    username: { type: 'text', notNull: true },
    email: { type: 'text', notNull: true },
    password_hash: { type: 'text', notNull: true },
    display_name: { type: 'text' },
    avatar_url: { type: 'text' },
    bio: { type: 'text' },
    email_verified_at: { type: 'timestamptz' },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
    updated_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  // Case-insensitive uniqueness: "Anna" and "anna" are the same username/
  // email for registration duplicate-checking purposes.
  pgm.createIndex('users', 'lower(username)', {
    name: 'users_username_lower_idx',
    unique: true,
  });
  pgm.createIndex('users', 'lower(email)', {
    name: 'users_email_lower_idx',
    unique: true,
  });
};

exports.down = (pgm) => {
  pgm.dropTable('users');
};
