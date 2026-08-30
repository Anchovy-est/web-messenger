// Loads and validates environment variables once, at startup, so the rest
// of the app can trust `env.X` instead of reaching into `process.env`
// (and reading `undefined` at some random point deep in a request).
require('dotenv').config();

function required(name, fallback) {
  const value = process.env[name] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),

  databaseUrl: required('DATABASE_URL'),

  jwtAccessSecret: required(
    'JWT_ACCESS_SECRET',
    process.env.NODE_ENV === 'test' ? 'test_access_secret' : undefined
  ),
  jwtRefreshSecret: required(
    'JWT_REFRESH_SECRET',
    process.env.NODE_ENV === 'test' ? 'test_refresh_secret' : undefined
  ),
  jwtAccessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',

  // The server-side master key ("KEK") for the one profile field (bio)
  // that's encrypted at rest rather than end-to-end — see
  // docs/ENCRYPTION.md for why bio gets this tier instead of the
  // client-held-key tier that message/media content uses. Read once here,
  // like the JWT secrets above, and never persisted anywhere — in
  // particular never written to the database, which is the whole point
  // of the "don't store keys in plaintext in the DB" requirement. Same
  // test-only fallback pattern as the JWT secrets; production deployments
  // must set a real one (any long random string — utils/fieldCrypto.js
  // hashes it down to a 32-byte AES-256 key, so the raw env value doesn't
  // need to be exactly 32 bytes itself).
  profileEncryptionKey: required(
    'PROFILE_ENCRYPTION_KEY',
    process.env.NODE_ENV === 'test'
      ? 'S4LyjPYqjukQ3eB8yz9VCzcMVAKl/IfGjctV2PprAtY='
      : undefined
  ),

  smtpHost: process.env.SMTP_HOST || '',
  smtpPort: Number(process.env.SMTP_PORT || 587),
  smtpUser: process.env.SMTP_USER || '',
  smtpPass: process.env.SMTP_PASS || '',
  smtpFrom: process.env.SMTP_FROM || 'Mobile Messenger <no-reply@mobile-messenger.local>',

  appBaseUrl: process.env.APP_BASE_URL || 'http://localhost:3000',

  // Path to a Firebase service-account JSON key, used to send push
  // notifications via the Admin SDK (see services/push.service.js).
  // Deliberately optional with no test/dev fallback (unlike the JWT and
  // encryption secrets above) — there's no meaningful fake credential
  // for a real external service, so push notifications simply stay
  // disabled (not an error) until a real Firebase project is set up and
  // this is pointed at it. See docs/PUSH_NOTIFICATIONS.md.
  firebaseServiceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH || '',

  maxUploadBytes: Number(process.env.MAX_UPLOAD_BYTES || 26214400),

  isProduction: process.env.NODE_ENV === 'production',
  isTest: process.env.NODE_ENV === 'test',
};

// The values docker-compose.yml (and the reset-password/JWT secrets in
// general) fall back to when nothing's been overridden — fine for local
// development, where the whole point is "works out of the box with zero
// setup", but a real deployment that forgets to override them would be
// trivially compromised (anyone reading this public repo can forge a
// valid JWT for any user, or recover the one profile field encrypted at
// rest, using a secret they already know). This is the one place that
// actually gets checked: refuse to start rather than silently run with
// a secret an attacker can read on GitHub. Only fires when
// NODE_ENV=production is actually set — which nothing in this repo's own
// docker-compose.yml does today (it's a local-dev file, deliberately),
// so this is a safety net for whenever a real deployment sets it, not a
// change to any behavior that exists here now.
const KNOWN_PLACEHOLDER_SECRETS = new Set([
  'dev_access_secret_change_me',
  'dev_refresh_secret_change_me',
  'dev_profile_encryption_key_change_me',
  'change_me_access_secret',
  'change_me_refresh_secret',
  'change_me_profile_encryption_key',
]);

if (env.isProduction) {
  const placeholders = [
    ['JWT_ACCESS_SECRET', env.jwtAccessSecret],
    ['JWT_REFRESH_SECRET', env.jwtRefreshSecret],
    ['PROFILE_ENCRYPTION_KEY', env.profileEncryptionKey],
  ].filter(([, value]) => KNOWN_PLACEHOLDER_SECRETS.has(value));

  if (placeholders.length > 0) {
    const names = placeholders.map(([name]) => name).join(', ');
    throw new Error(
      `Refusing to start in production with placeholder secret(s) still set: ${names}. ` +
        'Set real, unique values for these before deploying.'
    );
  }
}

module.exports = env;
