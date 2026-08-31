const { z } = require('zod');

// Same rules as registration's username — kept separate so the two
// can diverge later without entangling the registration flow.
const username = z
  .string()
  .trim()
  .min(3, 'Username must be at least 3 characters.')
  .max(20, 'Username must be at most 20 characters.')
  .regex(
    /^[a-zA-Z0-9_]+$/,
    'Username may only contain letters, numbers, and underscores.'
  );

// "About Me" — allowed to be empty, just capped so a profile can't
// hold unbounded text.
const bio = z.string().trim().max(300, 'About Me must be at most 300 characters.');

const updateProfileSchema = z.object({ username, bio });

// An X25519 public key is always 32 raw bytes, which base64-encodes
// to 44 characters. Shape check only — the server can't verify a
// value is actually a valid curve point; garbage here only breaks
// encryption for the sender themselves.
const updatePublicKeySchema = z.object({
  publicKey: z
    .string()
    .length(44, 'Invalid public key.')
    .regex(/^[A-Za-z0-9+/]{43}=$/, 'Invalid public key.'),
});

// Search term for GET /users/search. `.trim()` runs before `.min()`,
// so whitespace-only counts as empty too.
const searchQuerySchema = z.object({
  q: z
    .string()
    .trim()
    .min(1, 'Search query is required.')
    .max(100, 'Search query is too long.'),
});

// FCM device tokens are opaque strings with no fixed shape beyond
// "non-empty, not absurdly long" — actually verifying one is valid
// means calling Firebase, which push.service.js already does at send
// time, not registration time.
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
