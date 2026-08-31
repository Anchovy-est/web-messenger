// Data-access layer for `chats` / `chat_participants`. Invitation
// queries live in invitation.model.js — this file only knows about
// chats and who's in them.
const { query } = require('../config/db');

// `name` only matters for a group chat — a 1:1 chat's display name is
// derived client-side from the other participant, so existing 1:1
// call sites just leave it null.
async function createChat({ isGroup = false, createdBy, name = null }) {
  const result = await query(
    `INSERT INTO chats (is_group, created_by, name)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [isGroup, createdBy, name]
  );
  return result.rows[0];
}

async function addParticipant(chatId, userId) {
  await query(
    `INSERT INTO chat_participants (chat_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (chat_id, user_id) DO NOTHING`,
    [chatId, userId]
  );
}

// Used when sending an invitation: two users who already share a 1:1
// chat reuse it instead of getting a second one.
async function findDirectChatBetween(userIdA, userIdB) {
  const result = await query(
    `SELECT c.* FROM chats c
     WHERE c.is_group = false
       AND EXISTS (
         SELECT 1 FROM chat_participants cp
         WHERE cp.chat_id = c.id AND cp.user_id = $1
       )
       AND EXISTS (
         SELECT 1 FROM chat_participants cp
         WHERE cp.chat_id = c.id AND cp.user_id = $2
       )
     LIMIT 1`,
    [userIdA, userIdB]
  );
  return result.rows[0] || null;
}

// Shared shape for list and single-chat lookups: the other
// participant(s), plus the most recent message, which also serves as
// the sort key.
//
// `other` and `participants` are split by `is_group` on purpose — a
// 1:1 chat's `otherParticipant` shape predates groups and every client
// relies on it as-is, so it stays scoped to non-group chats rather
// than becoming "the first of several participants". `participants`
// is the group equivalent (everyone but the caller).
const CHAT_SELECT = `
  SELECT
    c.id, c.is_group, c.name, c.created_at,
    cp.archived_at,
    cp.muted_at,
    other.id AS other_user_id,
    other.username AS other_username,
    other.display_name AS other_display_name,
    other.avatar_url AS other_avatar_url,
    other.public_key AS other_public_key,
    grp.participants AS participants,
    lm.id AS last_message_id,
    lm.body AS last_message_body,
    lm.type AS last_message_type,
    lm.sender_id AS last_message_sender_id,
    lm.created_at AS last_message_at,
    COALESCE(lm.created_at, c.created_at) AS sort_key
  FROM chats c
  JOIN chat_participants cp ON cp.chat_id = c.id AND cp.user_id = $1
  LEFT JOIN LATERAL (
    SELECT u.id, u.username, u.display_name, u.avatar_url, u.public_key
    FROM chat_participants other_cp
    JOIN users u ON u.id = other_cp.user_id
    WHERE other_cp.chat_id = c.id AND other_cp.user_id != $1 AND NOT c.is_group
    LIMIT 1
  ) other ON true
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
      'id', u.id,
      'username', u.username,
      'displayName', u.display_name,
      'avatarUrl', u.avatar_url,
      'publicKey', u.public_key
    ) ORDER BY u.username) AS participants
    FROM chat_participants grp_cp
    JOIN users u ON u.id = grp_cp.user_id
    WHERE grp_cp.chat_id = c.id AND grp_cp.user_id != $1 AND c.is_group
  ) grp ON true
  LEFT JOIN LATERAL (
    SELECT id, body, type, sender_id, created_at
    FROM messages m
    WHERE m.chat_id = c.id AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC
    LIMIT 1
  ) lm ON true
`;

function toPublicChat(row) {
  if (!row) return null;
  return {
    id: row.id,
    isGroup: row.is_group,
    name: row.name,
    createdAt: row.created_at,
    archivedAt: row.archived_at,
    mutedAt: row.muted_at,
    otherParticipant: row.other_user_id
      ? {
          id: row.other_user_id,
          username: row.other_username,
          displayName: row.other_display_name,
          avatarUrl: row.other_avatar_url,
          // Used client-side to derive this chat's E2EE key via
          // X25519 ECDH. Null until the other participant has logged
          // in and registered a key.
          publicKey: row.other_public_key,
        }
      : null,
    // Every other participant of a group chat — null (not empty) for
    // a 1:1 chat, matching otherParticipant's own convention.
    participants: row.participants ?? null,
    lastMessage: row.last_message_id
      ? {
          id: row.last_message_id,
          body: row.last_message_body,
          type: row.last_message_type,
          senderId: row.last_message_sender_id,
          createdAt: row.last_message_at,
        }
      : null,
  };
}

// Only chats with 2+ participants are "real" — a pending invitation's
// chat sits at 1 participant until accepted, and stays there if
// declined. Neither belongs in a chat list.
async function listForUser(userId, { archived = false } = {}) {
  const result = await query(
    `${CHAT_SELECT}
     WHERE (cp.archived_at IS NOT NULL) = $2
       AND (SELECT COUNT(*) FROM chat_participants cp2 WHERE cp2.chat_id = c.id) >= 2
     ORDER BY sort_key DESC`,
    [userId, archived]
  );
  return result.rows.map(toPublicChat);
}

// The join in CHAT_SELECT already returns nothing if `userId` isn't a
// participant — no separate check needed.
async function findByIdForUser(chatId, userId) {
  const result = await query(`${CHAT_SELECT} WHERE c.id = $2`, [userId, chatId]);
  return toPublicChat(result.rows[0]);
}

// Every chat the user is in, archived or not — used at socket-connect
// time to join the realtime rooms that should push to this user.
async function listChatIdsForUser(userId) {
  const result = await query(
    `SELECT chat_id FROM chat_participants WHERE user_id = $1`,
    [userId]
  );
  return result.rows.map((row) => row.chat_id);
}

async function setArchived(chatId, userId, archived) {
  const result = await query(
    `UPDATE chat_participants
     SET archived_at = CASE WHEN $3 THEN now() ELSE NULL END
     WHERE chat_id = $1 AND user_id = $2
     RETURNING chat_id`,
    [chatId, userId, archived]
  );
  return result.rows.length > 0;
}

// Same shape as setArchived — only touches this one participant's row.
async function setMuted(chatId, userId, muted) {
  const result = await query(
    `UPDATE chat_participants
     SET muted_at = CASE WHEN $3 THEN now() ELSE NULL END
     WHERE chat_id = $1 AND user_id = $2
     RETURNING chat_id`,
    [chatId, userId, muted]
  );
  return result.rows.length > 0;
}

// Used before sending a push, to skip a recipient who muted this
// chat. Returns false for a non-participant too.
async function isMuted(chatId, userId) {
  const result = await query(
    'SELECT muted_at FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
    [chatId, userId]
  );
  return Boolean(result.rows[0]?.muted_at);
}

// Everyone else in the chat — who should be notified about something
// `userId` just did. Empty if `userId` is the only participant (a
// still-pending invitation), which is correct: nobody else has joined
// yet.
async function getOtherParticipantIds(chatId, userId) {
  const result = await query(
    'SELECT user_id FROM chat_participants WHERE chat_id = $1 AND user_id != $2',
    [chatId, userId]
  );
  return result.rows.map((row) => row.user_id);
}

// Plain membership check for authorizing group-only actions like
// inviting more people. `chatService.getChat` is what full read/write
// operations use instead, since those need the chat's data too.
async function isParticipant(chatId, userId) {
  const result = await query(
    'SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
    [chatId, userId]
  );
  return result.rows.length > 0;
}

module.exports = {
  createChat,
  addParticipant,
  findDirectChatBetween,
  listForUser,
  findByIdForUser,
  listChatIdsForUser,
  setArchived,
  setMuted,
  isMuted,
  getOtherParticipantIds,
  isParticipant,
};
