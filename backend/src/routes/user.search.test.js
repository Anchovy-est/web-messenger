// Integration test for user search against a real Postgres connection —
// see auth.routes.test.js for how to run this.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { createApp } = require('../app');
const { pool } = require('../config/db');

const app = createApp();

const runId = Date.now();
const createdUsernames = [];

async function registerAndLogin(label) {
  const username = `test_${label}_${runId}`.slice(0, 20);
  createdUsernames.push(username);
  const credentials = {
    username,
    email: `test_${label}_${runId}@example.com`,
    password: 'Password123!',
  };
  await request(app).post('/auth/register').send(credentials);
  const res = await request(app)
    .post('/auth/login')
    .send({ email: credentials.email, password: credentials.password });
  return { username, email: credentials.email, accessToken: res.body.accessToken };
}

async function search(accessToken, q) {
  return request(app)
    .get('/users/search')
    .query({ q })
    .set('Authorization', `Bearer ${accessToken}`);
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

test('finds an existing user by a partial username match', async () => {
  const target = await registerAndLogin('findme');
  const searcher = await registerAndLogin('searcher1');

  const res = await search(searcher.accessToken, target.username.slice(0, -3));

  assert.equal(res.status, 200);
  assert.ok(res.body.users.some((u) => u.username === target.username));
});

test('finds an existing user by exact email', async () => {
  const target = await registerAndLogin('findbyemail');
  const searcher = await registerAndLogin('searcher2');

  const res = await search(searcher.accessToken, target.email);

  assert.equal(res.status, 200);
  assert.equal(res.body.users.length, 1);
  assert.equal(res.body.users[0].email, target.email);
});

test('does not match on a partial email (exact match only, by design)', async () => {
  const target = await registerAndLogin('partialemail');
  const searcher = await registerAndLogin('searcher3');
  const partial = target.email.split('@')[0];

  const res = await search(searcher.accessToken, partial);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.users, []);
});

test('returns an empty list for a nonexistent user', async () => {
  const searcher = await registerAndLogin('searcher4');

  const res = await search(searcher.accessToken, `nobody_at_all_${runId}`);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.users, []);
});

test('returns multiple distinct results without duplicates when several users match', async () => {
  // Short, distinct labels — usernames are `test_<label>_<runId>` capped
  // at 20 chars, so a long/shared-prefix label here would truncate away
  // the very substring being searched for (or collide with another
  // test's username). Keep labels short and mutually distinct.
  const a = await registerAndLogin('dupa');
  const b = await registerAndLogin('dupb');
  const searcher = await registerAndLogin('searcher5');

  const res = await search(searcher.accessToken, 'dup');

  assert.equal(res.status, 200);
  const usernames = res.body.users.map((u) => u.username);
  assert.ok(usernames.includes(a.username));
  assert.ok(usernames.includes(b.username));
  assert.equal(new Set(usernames).size, usernames.length); // no duplicate rows
});

test('excludes the searching user from their own results', async () => {
  const self = await registerAndLogin('selfsearch');

  const res = await search(self.accessToken, self.username);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.users, []);
});

test('rejects an empty search with 400 VALIDATION_ERROR', async () => {
  const searcher = await registerAndLogin('emptysearch');

  const res = await search(searcher.accessToken, '');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('rejects a missing q parameter with 400 VALIDATION_ERROR', async () => {
  const searcher = await registerAndLogin('missingq');

  const res = await request(app)
    .get('/users/search')
    .set('Authorization', `Bearer ${searcher.accessToken}`);

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('rejects a whitespace-only search as invalid input', async () => {
  const searcher = await registerAndLogin('whitespace');

  const res = await search(searcher.accessToken, '   ');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('rejects an overly long search term as invalid input', async () => {
  const searcher = await registerAndLogin('toolong');

  const res = await search(searcher.accessToken, 'a'.repeat(101));

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('requires authentication', async () => {
  const res = await request(app).get('/users/search').query({ q: 'anything' });
  assert.equal(res.status, 401);
});

test('treats a literal "%" in the search term as literal text, not a SQL wildcard', async () => {
  const searcher = await registerAndLogin('wcs1');

  // An unescaped '%' would match every username in the table.
  const res = await search(searcher.accessToken, '%');

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.users, []);
});

test('treats a literal "_" in the search term as literal text, not a single-char SQL wildcard', async () => {
  const target = await registerAndLogin('wct');
  const searcher = await registerAndLogin('wcs2');
  // Same length as target.username with its last character swapped for
  // '_' — if '_' were an unescaped wildcard this would incorrectly match
  // target.username (any character in that position would satisfy it).
  const queryWithUnderscoreInWrongSpot = `${target.username.slice(0, -1)}_`;

  const res = await search(searcher.accessToken, queryWithUnderscoreInWrongSpot);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.users, []);
});
