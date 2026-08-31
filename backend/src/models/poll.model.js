// Data-access layer for `polls` / `poll_options` / `poll_votes`.
// Authorization is enforced one layer up, in poll.service.js — this
// file trusts the ids it's given, same as message.model.js.
const { query, withTransaction } = require('../config/db');

// Every option, with its live vote count and (for a non-anonymous
// poll) who voted for it — computed regardless of `is_anonymous`,
// then stripped by `toPublicPoll` below. Stripping in JS rather than
// branching the SQL keeps the "don't expose votes on an anonymous
// poll" rule in one easy-to-audit place.
//
// `mv` (my vote) is the viewer's own current choice, always
// populated whether the poll is anonymous or not — showing someone
// their own vote isn't an anonymity leak.
const POLL_SELECT = `
  SELECT
    p.id, p.message_id, p.chat_id, p.creator_id, p.question, p.is_anonymous, p.created_at,
    opts.options AS options,
    mv.option_id AS my_vote_option_id
  FROM polls p
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
      'id', po.id,
      'text', po.text,
      'position', po.position,
      'voteCount', v.vote_count,
      'voters', v.voters
    ) ORDER BY po.position) AS options
    FROM poll_options po
    LEFT JOIN LATERAL (
      SELECT COUNT(*)::int AS vote_count,
        json_agg(json_build_object(
          'id', u.id,
          'username', u.username,
          'displayName', u.display_name,
          'avatarUrl', u.avatar_url
        ) ORDER BY u.username) AS voters
      FROM poll_votes pv
      JOIN users u ON u.id = pv.user_id
      WHERE pv.option_id = po.id
    ) v ON true
    WHERE po.poll_id = p.id
  ) opts ON true
  LEFT JOIN poll_votes mv ON mv.poll_id = p.id AND mv.user_id = $2
`;

function toPublicPoll(row) {
  if (!row) return null;
  const options = (row.options || []).map((opt) => {
    const option = {
      id: opt.id,
      text: opt.text,
      position: opt.position,
      voteCount: opt.voteCount,
    };
    if (!row.is_anonymous) {
      option.voters = opt.voters || [];
    }
    return option;
  });
  const totalVotes = options.reduce((sum, opt) => sum + opt.voteCount, 0);
  return {
    id: row.id,
    messageId: row.message_id,
    chatId: row.chat_id,
    creatorId: row.creator_id,
    question: row.question,
    isAnonymous: row.is_anonymous,
    createdAt: row.created_at,
    totalVotes,
    options,
    // This viewer's own choice, or null if they haven't voted (or
    // retracted). Not an anonymity leak — see POLL_SELECT above.
    myVoteOptionId: row.my_vote_option_id,
  };
}

// `options` is an ordered array of option text — `position` is just
// its index, so callers never track it themselves.
async function createPoll({ messageId, chatId, creatorId, question, options, isAnonymous }) {
  const pollId = await withTransaction(async (client) => {
    const pollResult = await client.query(
      `INSERT INTO polls (message_id, chat_id, creator_id, question, is_anonymous)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id`,
      [messageId, chatId, creatorId, question, isAnonymous]
    );
    const id = pollResult.rows[0].id;
    for (let position = 0; position < options.length; position += 1) {
      await client.query(
        `INSERT INTO poll_options (poll_id, position, text) VALUES ($1, $2, $3)`,
        [id, position, options[position]]
      );
    }
    return id;
  });
  return findById(pollId, creatorId);
}

async function findById(pollId, viewerUserId) {
  const result = await query(`${POLL_SELECT} WHERE p.id = $1`, [pollId, viewerUserId]);
  return toPublicPoll(result.rows[0]);
}

async function findByMessageId(messageId, viewerUserId) {
  const result = await query(`${POLL_SELECT} WHERE p.message_id = $1`, [messageId, viewerUserId]);
  return toPublicPoll(result.rows[0]);
}

// Casts or changes a vote — one UPSERT either way, since
// (poll_id, user_id) is the primary key: there's only ever one row
// per user per poll. Caller has already checked `optionId` belongs to
// `pollId`.
async function vote(pollId, optionId, userId) {
  await query(
    `INSERT INTO poll_votes (poll_id, option_id, user_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (poll_id, user_id) DO UPDATE SET
       option_id = EXCLUDED.option_id,
       voted_at = now()`,
    [pollId, optionId, userId]
  );
}

// Idempotent — retracting a vote that doesn't exist just affects zero
// rows instead of erroring.
async function retractVote(pollId, userId) {
  await query(`DELETE FROM poll_votes WHERE poll_id = $1 AND user_id = $2`, [pollId, userId]);
}

module.exports = {
  createPoll,
  findById,
  findByMessageId,
  vote,
  retractVote,
};
