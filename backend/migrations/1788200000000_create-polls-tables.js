/* eslint-disable camelcase */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // `poll` joins the existing image/video/audio lineup of non-plain-text
  // message types (see init-messages-table.js) — a poll shows up in a
  // chat's timeline exactly like any other message, just with its own
  // question/options/votes living in the tables below instead of an
  // encrypted `body`.
  pgm.dropConstraint('messages', 'messages_type_check');
  pgm.addConstraint('messages', 'messages_type_check', {
    check: "type IN ('text', 'image', 'video', 'audio', 'poll')",
  });

  // One row per poll, 1:1 with the message that announces it — `poll_id`
  // isn't a column on `messages` (a poll message's own `body`/`media_url`
  // just stay null, same as any other type-specific column that doesn't
  // apply) so that a poll can be deleted (cascade) without a schema
  // change touching the messages table, and so message.model.js doesn't
  // need to know polls exist at all.
  //
  // `question`/options (see poll_options below) are deliberately *not*
  // end-to-end encrypted the way a text message's `body` is: the server
  // has to actively read them to validate votes, enforce one-vote-per-
  // user, tally results, and broadcast live updates to everyone in the
  // chat — none of which is possible without the server holding
  // plaintext to work with. This is the same trade-off most E2EE
  // messengers make for polls (Telegram, WhatsApp): the poll's content
  // is ordinary server-readable data, but *who voted for what* is still
  // protected by the ordinary chat-membership authorization every other
  // endpoint here already enforces, and, for an anonymous poll, further
  // withheld from the other participants in the chat (see
  // poll.model.js `toPublicPoll`) — never from the server itself, which
  // must know in order to prevent double voting and support changing/
  // retracting a vote.
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
    // Public (the default) shows every participant who voted for what;
    // anonymous shows only the tally. Fixed at creation — a poll can't
    // be switched from one to the other after votes may already have
    // been cast under the guarantee it started with.
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
    // Display order, matching the order the creator entered options in
    // — not alphabetical, not insertion-id order (which would happen to
    // match here, but shouldn't be relied on to).
    position: { type: 'integer', notNull: true },
    text: { type: 'text', notNull: true },
  });
  pgm.createIndex('poll_options', 'poll_id');

  // A single vote per (poll, user) — not per (option, user) — is exactly
  // what makes "change your vote" a plain UPDATE and "retract your vote"
  // a plain DELETE of one row, rather than needing to first clear out a
  // previous choice. Single-choice polls only (one option per vote); a
  // multi-select poll wasn't part of what was asked for here.
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
  // Tallying (COUNT/json_agg voters grouped by option, within one poll)
  // filters on option_id directly — the primary key above only helps
  // when the query already knows poll_id, which the per-option tally
  // subquery in poll.model.js doesn't.
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
