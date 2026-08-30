// Data-access layer for `messages` / `message_receipts`. Authorization (is
// this user even a participant of the chat?) is enforced one layer up, in
// message.service.js — this file trusts the chatId it's given.
const { query } = require('../config/db');

// Status is an objective property of the message, not "as seen by the
// caller": for a 1:1 chat there's exactly one possible recipient per
// message (whoever isn't the sender), so `recv_delivered_at`/
// `recv_read_at` mean the same thing regardless of who's asking.
//
// `deletedAt` is included in the public shape (unlike, say, an internal
// audit column) because a deleted message doesn't disappear from a
// chat — see `deleteMessage` below — it stays in place as a tombstone,
// and the client needs `deletedAt` to know to render it as one instead
// of showing its (now-nulled) body.
function toPublicMessage(row) {
  const status = row.recv_read_at ? 'read' : row.recv_delivered_at ? 'delivered' : 'sent';
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
  SELECT m.*, recv.delivered_at AS recv_delivered_at, recv.read_at AS recv_read_at
  FROM messages m
  LEFT JOIN LATERAL (
    SELECT delivered_at, read_at
    FROM message_receipts mr
    WHERE mr.message_id = m.id AND mr.user_id != m.sender_id
    LIMIT 1
  ) recv ON true
`;

// Deliberately does *not* filter out soft-deleted messages — callers
// (message.service.js) need to see a deleted message to correctly tell
// "doesn't exist / not in this chat" (404) apart from "exists, but
// already deleted" (also 404, checked explicitly via `deletedAt`) apart
// from "exists, sender mismatch" (403). Filtering here would collapse
// the second case into the first, silently.
async function findById(id) {
  const result = await query(`${MESSAGE_SELECT} WHERE m.id = $1`, [id]);
  return result.rows[0] ? toPublicMessage(result.rows[0]) : null;
}

// `body` and `mediaUrl` are both nullable in practice: a text message
// has a body and no mediaUrl; an image/video message has a mediaUrl and
// no body — there's no caption support, by design.
async function createMessage({ chatId, senderId, body = null, mediaUrl = null, type = 'text' }) {
  const result = await query(
    `INSERT INTO messages (chat_id, sender_id, type, body, media_url)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id`,
    [chatId, senderId, type, body, mediaUrl]
  );
  // A brand-new message never has a receipt row yet, so this could just
  // build the public shape directly with status: 'sent' — going back
  // through `findById` instead keeps `toPublicMessage`/`MESSAGE_SELECT` as
  // the single source of truth for that shape, at the cost of one extra
  // (indexed, cheap) query.
  return findById(result.rows[0].id);
}

// Cursor pagination for "load earlier messages": `before` is a message id.
// Without it, returns the most recent `limit` messages in the chat. With
// it, returns the `limit` messages that precede that message. Either way
// the result comes back oldest-first (ascending) — ready to render
// top-to-bottom with new messages appended at the bottom, matching
// `chat.model.js`'s ordering rule of "newest last".
//
// Deleted messages are included (as tombstones, body already nulled by
// `softDeleteMessage`) rather than filtered out — a deleted message
// needs an appropriate UI state, which means it stays in its place in
// the conversation instead of vanishing and reflowing everything
// around it.
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

// Marks every message in `chatId` sent by someone other than `userId` as
// delivered to `userId` (and, if `read` is true, also read) — `userId` is
// always the *recipient* here, never the sender. Idempotent and
// non-regressing: re-marking delivered never clears an existing read_at,
// and re-marking read never resets an existing timestamp to "now".
//
// Returns the ids of every message that IS now at least the requested
// status for this user (not just the ones this call changed) — re-
// announcing an already-reached status is harmless for a caller that
// just wants to push a status update, and saves tracking a separate
// "what actually changed" set. The one exception: a delivered-only pass
// excludes messages already read, so it never reports a downgrade.
async function markReceipt(chatId, userId, { read = false } = {}) {
  const result = await query(
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
     RETURNING message_id, (read_at IS NOT NULL) AS is_read`,
    [chatId, userId]
  );
  const rows = read ? result.rows : result.rows.filter((row) => !row.is_read);
  return {
    messageIds: rows.map((row) => row.message_id),
    status: read ? 'read' : 'delivered',
  };
}

// Caller (message.service.js `editMessage`) has already verified this
// message belongs to `id`'s sender and isn't deleted — this just does the
// write and hands back the fresh public shape (including the `editedAt`
// this call sets, and whatever status was already computed).
async function updateMessageBody(id, body) {
  await query(`UPDATE messages SET body = $1, edited_at = now() WHERE id = $2`, [body, id]);
  return findById(id);
}

// Soft-delete: sets `deleted_at` and nulls the content columns rather
// than removing the row. Nulling `body`/`media_url` — not just
// setting the timestamp — means the original content isn't sitting
// around retrievable from the database once "deleted"; the row survives
// only as a tombstone (id, chat, sender, timestamps) so the conversation
// keeps its shape instead of leaving a gap. Caller (message.service.js
// `deleteMessage`) has already verified this message belongs to `id`'s
// sender and isn't already deleted.
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
