// Data-access layer for `chats` / `chat_participants`. Invitation-specific
// queries live in invitation.model.js; this file only knows about chats
// and who's in them.
const { query } = require('../config/db');

// `name` is only ever meaningful for a group chat — a 1:1 chat's display
// name is derived client-side from the other participant (see
// `toPublicChat`'s `otherParticipant`), so every existing call site
// (1:1 invitations) simply omits it and gets the column's natural
// `NULL`, unchanged from before groups existed.
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

// Used by "send invitation" to enforce the rule that two users who
// already share a 1:1 chat don't need (and can't send) another
// invitation — they can just use the existing chat.
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

// Shared shape for both the list and single-chat lookups: who the other
// participant(s) are, and the most recent (non-deleted) message — which
// doubles as the sort key. A chat with no messages yet just sorts by its
// own created_at, and this same query reflects real activity the moment
// messages start landing, with no changes needed here.
//
// `other` (a single row) and `participants` (an array) are deliberately
// split by `is_group`, not just "whichever has data": a 1:1 chat's
// `otherParticipant` shape predates group chats and every existing
// client relies on it exactly as-is, so it stays scoped to `NOT
// c.is_group` rather than, say, becoming "the first of possibly several
// participants" once a chat has more than one other member — that would
// silently start returning an arbitrary participant instead of a group's
// actual roster. `participants` is the group equivalent — everyone
// *except* the caller, however many there are — and only ever populated
// for a group, so a 1:1 chat's payload isn't carrying a redundant
// single-element array alongside `otherParticipant`.
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
          // Needed client-side to derive this chat's end-to-end
          // encryption key (X25519 ECDH against my own private key,
          // which never leaves my device — see
          // lib/services/encryption_service.dart). Null until the other
          // participant has logged in at least once and registered a key.
          publicKey: row.other_public_key,
        }
      : null,
    // Every other participant of a *group* chat — null (not an empty
    // array) for a 1:1 chat, mirroring `otherParticipant`'s own "null
    // means not applicable" convention rather than conflating "no other
    // members" with "this isn't a group".
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

// Only chats with 2+ participants are "real" — a chat sits at 1
// participant (just the inviter) from the moment an invitation is sent
// until it's accepted (see invitation.service.js), and stays at 1
// forever if declined. Neither belongs in a chat list.
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

// The inner join on chat_participants (in CHAT_SELECT) means this
// naturally returns nothing if `userId` isn't a participant of `chatId`
// — no separate authorization check needed.
async function findByIdForUser(chatId, userId) {
  const result = await query(`${CHAT_SELECT} WHERE c.id = $2`, [userId, chatId]);
  return toPublicChat(result.rows[0]);
}

// Every chat the user is currently in, regardless of archived status —
// used at socket-connect time to join the realtime rooms that should
// push messages to this user.
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

// Same shape as setArchived — mutes/unmutes for exactly one participant,
// leaving the other's notification preference for this chat untouched.
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

// Used by push.service.js right before sending a push for a new
// message, to skip a recipient who's muted this specific chat. Returns
// `false` (not muted) for a non-participant too — a caller with no
// membership row has nothing to be muted from, and push.service.js
// already knows its recipient is a real participant by construction.
async function isMuted(chatId, userId) {
  const result = await query(
    'SELECT muted_at FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
    [chatId, userId]
  );
  return Boolean(result.rows[0]?.muted_at);
}

// Every other participant of a chat — i.e. "who should be notified
// about something `userId` just did in this chat". For a 1:1 chat
// that's at most one id; for a group, everyone else currently in it.
// Empty if `userId` is somehow the only participant (a still-pending,
// not-yet-accepted invitation's chat — push.service.js has nothing to
// notify in that case, which is correct: nobody's a recipient of a chat
// they haven't joined yet).
async function getOtherParticipantIds(chatId, userId) {
  const result = await query(
    'SELECT user_id FROM chat_participants WHERE chat_id = $1 AND user_id != $2',
    [chatId, userId]
  );
  return result.rows.map((row) => row.user_id);
}

// Membership check used to authorize group-only actions (inviting more
// people to an existing group — see invitation.service.js
// `inviteToChat`) — a plain boolean is enough here; `chatService.getChat`
// is what full read/write operations use instead, since those also need
// the chat's own data back, not just a yes/no.
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
