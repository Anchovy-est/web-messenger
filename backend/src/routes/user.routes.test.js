// Integration test for the profile endpoints against a real Postgres
// connection — see auth.routes.test.js for how to run this.
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
  return { username, accessToken: res.body.accessToken };
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

test('GET /users/me returns a fresh profile with default (empty) picture and bio', async () => {
  const { accessToken } = await registerAndLogin('freshprofile');

  const res = await request(app)
    .get('/users/me')
    .set('Authorization', `Bearer ${accessToken}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.user.avatarUrl, null);
  assert.equal(res.body.user.bio, null);
});

test('GET /users/me requires authentication', async () => {
  const res = await request(app).get('/users/me');
  assert.equal(res.status, 401);
});

test('PUT /users/me updates username and bio, and it persists on re-fetch', async () => {
  const { username, accessToken } = await registerAndLogin('updateprofile');
  const newUsername = `${username}x`.slice(0, 20);
  createdUsernames.push(newUsername);

  const putRes = await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ username: newUsername, bio: 'Hello world' });

  assert.equal(putRes.status, 200);
  assert.equal(putRes.body.user.username, newUsername);
  assert.equal(putRes.body.user.bio, 'Hello world');

  const getRes = await request(app)
    .get('/users/me')
    .set('Authorization', `Bearer ${accessToken}`);
  assert.equal(getRes.body.user.username, newUsername);
  assert.equal(getRes.body.user.bio, 'Hello world');
});

test('PUT /users/me allows re-saving your own unchanged username', async () => {
  const { username, accessToken } = await registerAndLogin('resaveself');

  const res = await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ username, bio: 'still me' });

  assert.equal(res.status, 200);
  assert.equal(res.body.user.username, username);
});

test('PUT /users/me rejects a username already taken by someone else', async () => {
  const first = await registerAndLogin('taken1');
  const second = await registerAndLogin('taken2');

  const res = await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${second.accessToken}`)
    .send({ username: first.username, bio: '' });

  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, 'USERNAME_TAKEN');
});

test('PUT /users/me allows clearing the bio to an empty string', async () => {
  const { username, accessToken } = await registerAndLogin('clearbio');
  await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ username, bio: 'something' });

  const res = await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ username, bio: '' });

  assert.equal(res.status, 200);
  assert.equal(res.body.user.bio, '');
});

test('PUT /users/me rejects a bio over 300 characters', async () => {
  const { username, accessToken } = await registerAndLogin('longbio');

  const res = await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ username, bio: 'a'.repeat(301) });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('PUT /users/me requires authentication', async () => {
  const res = await request(app).put('/users/me').send({ username: 'x', bio: '' });
  assert.equal(res.status, 401);
});

// --- Bio is encrypted at rest -----------------------------------------

test('PUT /users/me stores bio encrypted at rest, not as plaintext', async () => {
  const { username, accessToken } = await registerAndLogin('encbio');
  const plaintext = 'This is my private About Me text.';

  const putRes = await request(app)
    .put('/users/me')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ username, bio: plaintext });
  assert.equal(putRes.status, 200);
  // The API itself still hands the owner back their own plaintext.
  assert.equal(putRes.body.user.bio, plaintext);

  // The actual check that matters: the stored value must not contain
  // the plaintext, regardless of what any endpoint returns.
  const { rows } = await pool.query('SELECT bio FROM users WHERE username = $1', [username]);
  assert.equal(rows.length, 1);
  const storedBio = rows[0].bio;
  assert.ok(storedBio, 'expected a stored value');
  assert.notEqual(storedBio, plaintext);
  assert.ok(
    !storedBio.includes(plaintext),
    'raw bio column must not contain the plaintext substring'
  );
  // Shape-check it's a real AES-256-GCM envelope: base64 of
  // nonce(12) + ciphertext + authTag(16).
  const raw = Buffer.from(storedBio, 'base64');
  assert.ok(raw.length >= 12 + 16);

  const getRes = await request(app)
    .get('/users/me')
    .set('Authorization', `Bearer ${accessToken}`);
  assert.equal(getRes.body.user.bio, plaintext);
});

// --- End-to-end encryption public key ----------------------------------

test('PUT /users/me/public-key registers a public key, visible to the owner', async () => {
  const { accessToken } = await registerAndLogin('pubkey1');
  // Syntactically valid X25519-public-key shape: 32 raw bytes, base64.
  const publicKey = Buffer.alloc(32, 7).toString('base64');

  const res = await request(app)
    .put('/users/me/public-key')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ publicKey });

  assert.equal(res.status, 200);
  assert.equal(res.body.user.publicKey, publicKey);

  const getRes = await request(app)
    .get('/users/me')
    .set('Authorization', `Bearer ${accessToken}`);
  assert.equal(getRes.body.user.publicKey, publicKey);
});

test('PUT /users/me/public-key rejects a malformed key', async () => {
  const { accessToken } = await registerAndLogin('pubkey2');

  const res = await request(app)
    .put('/users/me/public-key')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ publicKey: 'not-a-real-key' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'VALIDATION_ERROR');
});

test('PUT /users/me/public-key requires authentication', async () => {
  const res = await request(app).put('/users/me/public-key').send({ publicKey: 'x' });
  assert.equal(res.status, 401);
});
