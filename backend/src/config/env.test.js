// Covers the production placeholder-secret guard added to env.js —
// isolated from the rest of the suite (which needs the real, already-
// loaded `env` singleton) by manipulating `process.env` and the module
// cache directly, then restoring both afterward.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const ENV_PATH = require.resolve('./env');
const TOUCHED_KEYS = [
  'NODE_ENV',
  'DATABASE_URL',
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
  'PROFILE_ENCRYPTION_KEY',
];

function withEnv(overrides, fn) {
  const saved = {};
  for (const key of TOUCHED_KEYS) saved[key] = process.env[key];
  Object.assign(process.env, overrides);
  delete require.cache[ENV_PATH];

  try {
    return fn();
  } finally {
    for (const key of TOUCHED_KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
    delete require.cache[ENV_PATH];
    // Re-require with the real environment restored so every other test
    // file's already-cached `env` (or a fresh require of it later in
    // this same file) reflects the actual test configuration again, not
    // whatever this test just simulated.
    require('./env');
  }
}

test('refuses to start in production with a known placeholder JWT secret', () => {
  assert.throws(
    () =>
      withEnv(
        {
          NODE_ENV: 'production',
          DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
          JWT_ACCESS_SECRET: 'dev_access_secret_change_me',
          JWT_REFRESH_SECRET: 'a-real-unique-refresh-secret',
          PROFILE_ENCRYPTION_KEY: 'a-real-unique-encryption-key',
        },
        () => require(ENV_PATH)
      ),
    /placeholder secret/
  );
});

test('refuses to start in production with a known placeholder encryption key', () => {
  assert.throws(
    () =>
      withEnv(
        {
          NODE_ENV: 'production',
          DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
          JWT_ACCESS_SECRET: 'a-real-unique-access-secret',
          JWT_REFRESH_SECRET: 'a-real-unique-refresh-secret',
          PROFILE_ENCRYPTION_KEY: 'dev_profile_encryption_key_change_me',
        },
        () => require(ENV_PATH)
      ),
    /placeholder secret/
  );
});

test('starts normally in production with real, unique secrets', () => {
  const result = withEnv(
    {
      NODE_ENV: 'production',
      DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
      JWT_ACCESS_SECRET: 'a-real-unique-access-secret',
      JWT_REFRESH_SECRET: 'a-real-unique-refresh-secret',
      PROFILE_ENCRYPTION_KEY: 'a-real-unique-encryption-key',
    },
    () => require(ENV_PATH)
  );

  assert.equal(result.isProduction, true);
});

test('placeholder secrets are only rejected in production, not development', () => {
  const result = withEnv(
    {
      NODE_ENV: 'development',
      DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
      JWT_ACCESS_SECRET: 'dev_access_secret_change_me',
      JWT_REFRESH_SECRET: 'dev_refresh_secret_change_me',
      PROFILE_ENCRYPTION_KEY: 'dev_profile_encryption_key_change_me',
    },
    () => require(ENV_PATH)
  );

  assert.equal(result.isProduction, false);
});
