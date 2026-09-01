// Covers env.js's production placeholder-secret guard, isolated from
// the rest of the suite by manipulating process.env and the module
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
  'CORS_ORIGINS',
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
    // Re-require with the real environment restored, so every other
    // cached `env` reflects the actual test config again.
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

test('starts normally in production with real, unique secrets and CORS_ORIGINS set', () => {
  const result = withEnv(
    {
      NODE_ENV: 'production',
      DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
      JWT_ACCESS_SECRET: 'a-real-unique-access-secret',
      JWT_REFRESH_SECRET: 'a-real-unique-refresh-secret',
      PROFILE_ENCRYPTION_KEY: 'a-real-unique-encryption-key',
      CORS_ORIGINS: 'https://example.com',
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
      CORS_ORIGINS: '',
    },
    () => require(ENV_PATH)
  );

  assert.equal(result.isProduction, false);
});

// --- CORS_ORIGINS ----------------------------------------------------

test('parses CORS_ORIGINS into a trimmed, comma-separated list', () => {
  const result = withEnv(
    {
      NODE_ENV: 'test', // so the JWT/encryption-key fallbacks apply — irrelevant to this test
      DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
      CORS_ORIGINS: ' https://a.example.com ,https://b.example.com',
    },
    () => require(ENV_PATH)
  );

  assert.deepEqual(result.corsOrigins, ['https://a.example.com', 'https://b.example.com']);
});

test('an unset CORS_ORIGINS parses to an empty list outside production', () => {
  const result = withEnv(
    { NODE_ENV: 'test', DATABASE_URL: 'postgres://user:pass@localhost:5432/db', CORS_ORIGINS: '' },
    () => require(ENV_PATH)
  );

  assert.deepEqual(result.corsOrigins, []);
});

test('refuses to start in production without CORS_ORIGINS set', () => {
  assert.throws(
    () =>
      withEnv(
        {
          NODE_ENV: 'production',
          DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
          JWT_ACCESS_SECRET: 'a-real-unique-access-secret',
          JWT_REFRESH_SECRET: 'a-real-unique-refresh-secret',
          PROFILE_ENCRYPTION_KEY: 'a-real-unique-encryption-key',
          CORS_ORIGINS: '',
        },
        () => require(ENV_PATH)
      ),
    /CORS_ORIGINS/
  );
});
