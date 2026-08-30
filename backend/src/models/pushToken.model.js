// Data-access layer for `push_tokens` — one row per device (see the
// migration for why it's per-device, not per-user).
const { query } = require('../config/db');

// Upsert: a device re-registering (app restart, token refresh from
// Firebase) just updates its existing row; a token that shows up under a
// different account (logout/login as someone else on the same device)
// gets reassigned rather than left orphaned under the old owner.
async function register(userId, token, platform) {
  await query(
    `INSERT INTO push_tokens (user_id, token, platform)
     VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform`,
    [userId, token, platform]
  );
}

// Called on logout — a signed-out device shouldn't keep receiving this
// user's pushes.
async function unregister(userId, token) {
  await query('DELETE FROM push_tokens WHERE user_id = $1 AND token = $2', [userId, token]);
}

async function listForUser(userId) {
  const result = await query('SELECT token FROM push_tokens WHERE user_id = $1', [userId]);
  return result.rows.map((row) => row.token);
}

// Called by push.service.js when Firebase reports a token as no longer
// registered (the app was uninstalled, or the token expired) — cheap
// hygiene so a dead token isn't retried forever.
async function remove(token) {
  await query('DELETE FROM push_tokens WHERE token = $1', [token]);
}

module.exports = { register, unregister, listForUser, remove };
