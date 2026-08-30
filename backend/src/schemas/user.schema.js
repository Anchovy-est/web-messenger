const { z } = require('zod');

// Same rules as registration's username (see auth.schema.js) — kept
// separate rather than shared so the two can diverge later (e.g. if
// profile editing ever needs a cooldown or different constraints)
// without entangling the registration flow.
const username = z
  .string()
  .trim()
  .min(3, 'Username must be at least 3 characters.')
  .max(20, 'Username must be at most 20 characters.')
  .regex(
    /^[a-zA-Z0-9_]+$/,
    'Username may only contain letters, numbers, and underscores.'
  );

// "About Me" — allowed to be an empty string (that's the default state),
// just capped so a profile can't hold an unbounded amount of text.
const bio = z.string().trim().max(300, 'About Me must be at most 300 characters.');

const updateProfileSchema = z.object({ username, bio });

// An X25519 public key is always exactly 32 raw bytes, which
// base64-encodes to 44 characters (43 content chars + one '=' padding
// char). This is a shape check only — the server has no way to verify a
// submitted value is actually a valid curve point, same as it can't
// verify a JWT's signing key is "real"; a client sending garbage here
// only breaks encryption for itself; other participants' payloads and
// message plaintext are unaffected.
const updatePublicKeySchema = z.object({
  publicKey: z
    .string()
    .length(44, 'Invalid public key.')
    .regex(/^[A-Za-z0-9+/]{43}=$/, 'Invalid public key.'),
});

// Search term for GET /users/search. `.trim()` runs before `.min()`, so a
// whitespace-only value (" ") is rejected the same way an empty one is —
// both are "no real search term" from the caller's point of view.
const searchQuerySchema = z.object({
  q: z
    .string()
    .trim()
    .min(1, 'Search query is required.')
    .max(100, 'Search query is too long.'),
});

// FCM device tokens are opaque, variable-length strings with no fixed
// shape the server can meaningfully validate beyond "non-empty, not
// absurdly long" — same posture as the public key schema above:
// verifying it's a *real*, currently-valid token would mean actually
// calling Firebase, which push.service.js already does (and handles a
// stale one gracefully) at send time, not at registration time.
const registerPushTokenSchema = z.object({
  token: z.string().trim().min(1, 'Token is required.').max(4096, 'Token is too long.'),
  platform: z.enum(['android', 'ios']).optional().default('android'),
});

const unregisterPushTokenSchema = z.object({
  token: z.string().trim().min(1, 'Token is required.'),
});

module.exports = {
  updateProfileSchema,
  searchQuerySchema,
  updatePublicKeySchema,
  registerPushTokenSchema,
  unregisterPushTokenSchema,
};
