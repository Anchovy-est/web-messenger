// Data-access layer for `chat_invitations`. Every read joins in basic
// inviter/invitee info so the API layer never needs a second round
// trip just to say whose invitation this is.
const { query } = require('../config/db');

// Also joins in the target chat's is_group/name — otherwise the
// client couldn't tell a 1:1 invitation apart from a group one.
const SELECT_WITH_USERS = `
  SELECT
    ci.id, ci.chat_id, ci.status, ci.created_at, ci.responded_at,
    c.is_group AS chat_is_group, c.name AS chat_name,
    inviter.id   AS inviter_id,   inviter.username   AS inviter_username,
    inviter.display_name AS inviter_display_name, inviter.avatar_url AS inviter_avatar_url,
    invitee.id   AS invitee_id,   invitee.username   AS invitee_username,
    invitee.display_name AS invitee_display_name, invitee.avatar_url AS invitee_avatar_url
  FROM chat_invitations ci
  JOIN chats c ON c.id = ci.chat_id
  JOIN users inviter ON inviter.id = ci.inviter_id
  JOIN users invitee ON invitee.id = ci.invitee_id
`;

function toPublicInvitation(row) {
  if (!row) return null;
  return {
    id: row.id,
    chatId: row.chat_id,
    status: row.status,
    createdAt: row.created_at,
    respondedAt: row.responded_at,
    chat: {
      id: row.chat_id,
      isGroup: row.chat_is_group,
      name: row.chat_name,
    },
    inviter: {
      id: row.inviter_id,
      username: row.inviter_username,
      displayName: row.inviter_display_name,
      avatarUrl: row.inviter_avatar_url,
    },
    invitee: {
      id: row.invitee_id,
      username: row.invitee_username,
      displayName: row.invitee_display_name,
      avatarUrl: row.invitee_avatar_url,
    },
  };
}

async function create({ chatId, inviterId, inviteeId }) {
  const result = await query(
    `INSERT INTO chat_invitations (chat_id, inviter_id, invitee_id)
     VALUES ($1, $2, $3)
     RETURNING id`,
    [chatId, inviterId, inviteeId]
  );
  return findById(result.rows[0].id);
}

async function findById(id) {
  const result = await query(`${SELECT_WITH_USERS} WHERE ci.id = $1`, [id]);
  return toPublicInvitation(result.rows[0]);
}

// Blocks a second invitation while one's already pending between the
// same two people, regardless of who invited whom or which chat.
async function findPendingBetween(userIdA, userIdB) {
  const result = await query(
    `${SELECT_WITH_USERS}
     WHERE ci.status = 'pending'
       AND ((ci.inviter_id = $1 AND ci.invitee_id = $2)
         OR (ci.inviter_id = $2 AND ci.invitee_id = $1))
     LIMIT 1`,
    [userIdA, userIdB]
  );
  return toPublicInvitation(result.rows[0]);
}

// Group-chat equivalent of findPendingBetween, scoped to one chat —
// the same two people can share several group chats, each with its
// own invitation history. Blocks re-inviting someone already invited
// to this group who hasn't responded yet.
async function findPendingForChat(chatId, inviteeId) {
  const result = await query(
    `${SELECT_WITH_USERS}
     WHERE ci.status = 'pending' AND ci.chat_id = $1 AND ci.invitee_id = $2
     LIMIT 1`,
    [chatId, inviteeId]
  );
  return toPublicInvitation(result.rows[0]);
}

async function listReceived(userId, { status } = {}) {
  const params = [userId];
  let where = 'ci.invitee_id = $1';
  if (status) {
    params.push(status);
    where += ` AND ci.status = $${params.length}`;
  }
  const result = await query(
    `${SELECT_WITH_USERS} WHERE ${where} ORDER BY ci.created_at DESC`,
    params
  );
  return result.rows.map(toPublicInvitation);
}

async function listSent(userId, { status } = {}) {
  const params = [userId];
  let where = 'ci.inviter_id = $1';
  if (status) {
    params.push(status);
    where += ` AND ci.status = $${params.length}`;
  }
  const result = await query(
    `${SELECT_WITH_USERS} WHERE ${where} ORDER BY ci.created_at DESC`,
    params
  );
  return result.rows.map(toPublicInvitation);
}

async function updateStatus(id, status) {
  const result = await query(
    `UPDATE chat_invitations SET status = $1, responded_at = now()
     WHERE id = $2
     RETURNING id`,
    [status, id]
  );
  if (!result.rows[0]) return null;
  return findById(result.rows[0].id);
}

module.exports = {
  create,
  findById,
  findPendingBetween,
  findPendingForChat,
  listReceived,
  listSent,
  updateStatus,
};
