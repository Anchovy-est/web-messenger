// Integration test against the real Express app + a real Postgres
// connection (no mocking the DB layer) — run with the docker-compose
// `db` service up, e.g.:
//   DATABASE_URL=postgres://messenger:messenger@localhost:5432/messenger npm test
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { createApp } = require('../app');
const { pool } = require('../config/db');

const app = createApp();

// Unique per test run so re-running this file doesn't collide with
// leftover rows from a previous run that failed before cleanup.
const runId = Date.now();
const createdUsernames = [];

function uniqueUser(label) {
  const username = `test_${label}_${runId}`.slice(0, 20);
  createdUsernames.push(username);
  return {
    username,
    email: `test_${label}_${runId}@example.com`,
    password: 'Password123!',
  };
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

test('POST /auth/register creates a user and never returns the password hash', async () => {
  const payload = uniqueUser('register');

  const res = await request(app).post('/auth/register').send(payload);

  assert.equal(res.status, 201);
  assert.equal(res.body.user.username, payload.username);
  assert.equal(res.body.user.email, payload.email);
  assert.equal(res.body.user.emailVerified, false);
  assert.equal('password' in res.body.user, false);
  assert.equal('passwordHash' in res.body.user, false);
  assert.equal('password_hash' in res.body.user, false);
});

test('POST /auth/register rejects a duplicate email with 409 EMAIL_TAKEN', async () => {
  const first = uniqueUser('dupemail1');
  const second = uniqueUser('dupemail2');
  await request(app).post('/auth/register').send(first);

  const res = await request(app)
    .post('/auth/register')
    .send({ ...second, email: first.email });

  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, 'EMAIL_TAKEN');
});

test('POST /auth/register rejects a duplicate username (case-insensitive) with 409 USERNAME_TAKEN', async () => {
  const payload = uniqueUser('dupuser');
  await request(app).post('/auth/register').send(payload);

  const res = await request(app)
    .post('/auth/register')
    .send({
      ...payload,
      username: payload.username.toUpperCase(),
      email: `other_${payload.email}`,
    });

  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, 'USERNAME_TAKEN');
});

test('POST /auth/register rejects a weak password with 400 VALIDATION_ERROR', async () => {
  const payload = uniqueUser('weakpw');

  const res = await request(app)
    .post('/auth/register')
    .send({ ...payload, password: 'short' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
  assert.ok(res.body.error.details.some((d) => d.field === 'password'));
});

// Each of these satisfies every rule *except* the one it's named for,
// pinning down that the strength check actually enforces all five —
// not just "8+ chars and some letter/digit", which is all it used to
// check (see git history on auth.schema.js).
const weakPasswords = {
  'too short': 'Sh0rt!1',
  'no lowercase letter': 'ALLUPPER123!',
  'no uppercase letter': 'alllower123!',
  'no digit': 'NoDigitsHere!',
  'no special character': 'NoSpecialChar123',
};

for (const [reason, password] of Object.entries(weakPasswords)) {
  test(`POST /auth/register rejects a password with ${reason}`, async () => {
    const payload = uniqueUser(`weakpw_${reason.replace(/\s+/g, '')}`);

    const res = await request(app)
      .post('/auth/register')
      .send({ ...payload, password });

    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    assert.ok(res.body.error.details.some((d) => d.field === 'password'));
  });
}

test('POST /auth/register accepts a password meeting all five strength rules', async () => {
  const payload = uniqueUser('strongpw');

  const res = await request(app)
    .post('/auth/register')
    .send({ ...payload, password: 'Str0ng!Pass' });

  assert.equal(res.status, 201);
});
