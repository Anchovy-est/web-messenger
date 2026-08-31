/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // `poll` joins the image/video/audio lineup of non-text message
  // types — a poll shows up in the timeline like any other message,
  // with its own question/options/votes in the tables below instead
  // of an encrypted `body`.
  pgm.dropConstraint('messages', 'messages_type_check');
  pgm.addConstraint('messages', 'messages_type_check', {
    check: "type IN ('text', 'image', 'video', 'audio', 'poll')",
  });

  // One row per poll, 1:1 with the message that announces it.
  //
  // question/options are deliberately not end-to-end encrypted like a
  // text message's body — the server has to read them to validate
  // votes, enforce one-vote-per-user, tally results, and broadcast
  // live updates. Same trade-off most E2EE messengers make for polls:
  // content is server-readable, but who-voted-for-what stays behind
  // normal chat-membership authorization, and is withheld from other
  // participants for an anonymous poll (never from the server itself,
  // which needs it to prevent double voting).
  pgm.createTable('polls', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    message_id: {
      type: 'uuid',
      notNull: true,
      unique: true,
      references: 'messages',
      onDelete: 'CASCADE',
    },
    chat_id: {
      type: 'uuid',
      notNull: true,
      references: 'chats',
      onDelete: 'CASCADE',
    },
    creator_id: {
      type: 'uuid',
      references: 'users',
      onDelete: 'SET NULL',
    },
    question: { type: 'text', notNull: true },
    // Public (default) shows who voted for what; anonymous shows only
    // the tally. Fixed at creation — can't switch after votes exist.
    is_anonymous: { type: 'boolean', notNull: true, default: false },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });
  pgm.createIndex('polls', 'chat_id');

  pgm.createTable('poll_options', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    poll_id: {
      type: 'uuid',
      notNull: true,
      references: 'polls',
      onDelete: 'CASCADE',
    },
    // Display order, matching how the creator entered options — not
    // alphabetical or insertion order.
    position: { type: 'integer', notNull: true },
    text: { type: 'text', notNull: true },
  });
  pgm.createIndex('poll_options', 'poll_id');

  // One vote per (poll, user), not per (option, user) — that's what
  // makes "change vote" a plain UPDATE and "retract" a plain DELETE.
  // Single-choice only.
  pgm.createTable('poll_votes', {
    poll_id: {
      type: 'uuid',
      notNull: true,
      references: 'polls',
      onDelete: 'CASCADE',
    },
    option_id: {
      type: 'uuid',
      notNull: true,
      references: 'poll_options',
      onDelete: 'CASCADE',
    },
    user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    voted_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });
  pgm.addConstraint('poll_votes', 'poll_votes_pkey', {
    primaryKey: ['poll_id', 'user_id'],
  });
  // Tallying filters on option_id directly — the primary key above
  // only helps when poll_id is already known.
  pgm.createIndex('poll_votes', 'option_id');
};

exports.down = (pgm) => {
  pgm.dropTable('poll_votes');
  pgm.dropTable('poll_options');
  pgm.dropTable('polls');
  pgm.dropConstraint('messages', 'messages_type_check');
  pgm.addConstraint('messages', 'messages_type_check', {
    check: "type IN ('text', 'image', 'video', 'audio')",
  });
};
