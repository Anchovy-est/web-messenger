// Data-access layer for `messages` / `message_receipts`. Authorization
// lives one layer up in message.service.js — this file trusts the
// chatId it's given.
const { query } = require('../config/db');

// Status is "delivered"/"read" only once every other participant has
// it delivered/read, not just whichever one is asking. A recipient
// with no receipt row yet counts as "not delivered".
//
// `deletedAt` is in the public shape because a deleted message stays
// in the chat as a tombstone instead of disappearing.
function toPublicMessage(row) {
  const status = row.recv_all_read ? 'read' : row.recv_all_delivered ? 'delivered' : 'sent';
  return {
    id: row.id,
    chatId: row.chat_id,
    senderId: row.sender_id,
    type: row.type,
    body: row.body,
    mediaUrl: row.media_url,
    createdAt: row.created_at,
    editedAt: row.edited_at,
    deletedAt: row.deleted_at,
    status,
  };
}

const MESSAGE_SELECT = `
  SELECT m.*,
    recv.all_delivered AS recv_all_delivered,
    recv.all_read AS recv_all_read
  FROM messages m
  LEFT JOIN LATERAL (
    SELECT
      bool_and(mr.delivered_at IS NOT NULL) AS all_delivered,
      bool_and(mr.read_at IS NOT NULL) AS all_read
    FROM chat_participants cp
    LEFT JOIN message_receipts mr ON mr.message_id = m.id AND mr.user_id = cp.user_id
    WHERE cp.chat_id = m.chat_id AND cp.user_id != m.sender_id
  ) recv ON true
`;

// Doesn't filter out soft-deleted messages — callers need to tell
// "not found" apart from "found, but deleted" apart from "found, but
// not yours".
async function findById(id) {
  const result = await query(`${MESSAGE_SELECT} WHERE m.id = $1`, [id]);
  return result.rows[0] ? toPublicMessage(result.rows[0]) : null;
}

// `body`/`mediaUrl` are mutually exclusive in practice — no caption
// support, by design.
async function createMessage({ chatId, senderId, body = null, mediaUrl = null, type = 'text' }) {
  const result = await query(
    `INSERT INTO messages (chat_id, sender_id, type, body, media_url)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id`,
    [chatId, senderId, type, body, mediaUrl]
  );
  // A new message is always 'sent', but routing back through
  // findById keeps toPublicMessage as the one source of truth.
  return findById(result.rows[0].id);
}

// Cursor pagination for "load earlier messages": `before` is a
// message id. Result always comes back oldest-first.
//
// Deleted messages stay in the list as tombstones instead of being
// filtered out, so the conversation doesn't reflow around them.
async function listForChat(chatId, { limit = 50, before } = {}) {
  const params = [chatId, limit];
  let cursorClause = '';
  if (before) {
    params.push(before);
    cursorClause = `AND m.created_at < (SELECT created_at FROM messages WHERE id = $3)`;
  }

  const result = await query(
    `${MESSAGE_SELECT}
     WHERE m.chat_id = $1 ${cursorClause}
     ORDER BY m.created_at DESC
     LIMIT $2`,
    params
  );
  return result.rows.reverse().map(toPublicMessage);
}

// Marks every message in `chatId` sent by someone other than `userId`
// as delivered (and read, if requested) for `userId`. Idempotent: never
// clears an existing read_at or resets a timestamp that's already set.
//
// Returns the ids of messages that just reached that status *overall*
// (every participant, not just this one) — for a 1:1 chat that's the
// same as this ack, but in a group it may take more than one. A
// delivered-only pass skips messages already fully read.
async function markReceipt(chatId, userId, { read = false } = {}) {
  const upserted = await query(
    `INSERT INTO message_receipts (message_id, user_id, delivered_at, read_at)
     SELECT m.id, $2, now(), ${read ? 'now()' : 'NULL'}
     FROM messages m
     WHERE m.chat_id = $1
       AND m.sender_id IS NOT NULL
       AND m.sender_id != $2
       AND m.deleted_at IS NULL
     ON CONFLICT (message_id, user_id) DO UPDATE SET
       delivered_at = COALESCE(message_receipts.delivered_at, EXCLUDED.delivered_at),
       read_at = COALESCE(message_receipts.read_at, EXCLUDED.read_at)
     RETURNING message_id`,
    [chatId, userId]
  );
  const touchedIds = upserted.rows.map((row) => row.message_id);
  if (touchedIds.length === 0) {
    return { messageIds: [], status: read ? 'read' : 'delivered' };
  }

  // Only re-checks the messages this call touched, so a message that
  // already reached its overall status via someone else's ack isn't
  // re-announced every time.
  const aggregate = await query(
    `SELECT m.id AS message_id,
       bool_and(mr.delivered_at IS NOT NULL) AS all_delivered,
       bool_and(mr.read_at IS NOT NULL) AS all_read
     FROM messages m
     JOIN chat_participants cp ON cp.chat_id = m.chat_id AND cp.user_id != m.sender_id
     LEFT JOIN message_receipts mr ON mr.message_id = m.id AND mr.user_id = cp.user_id
     WHERE m.id = ANY($1::uuid[])
     GROUP BY m.id`,
    [touchedIds]
  );
  const messageIds = aggregate.rows
    .filter((row) => (read ? row.all_read : row.all_delivered && !row.all_read))
    .map((row) => row.message_id);

  return { messageIds, status: read ? 'read' : 'delivered' };
}

// Caller has already checked ownership and that the message isn't
// deleted — this just writes and returns the fresh public shape.
async function updateMessageBody(id, body) {
  await query(`UPDATE messages SET body = $1, edited_at = now() WHERE id = $2`, [body, id]);
  return findById(id);
}

// Soft-delete: sets deleted_at and nulls the content columns instead
// of removing the row, so the conversation keeps its shape and no
// deleted content lingers in the database.
async function softDeleteMessage(id) {
  await query(
    `UPDATE messages SET deleted_at = now(), body = NULL, media_url = NULL WHERE id = $1`,
    [id]
  );
  return findById(id);
}

module.exports = {
  findById,
  createMessage,
  listForChat,
  markReceipt,
  updateMessageBody,
  softDeleteMessage,
};
