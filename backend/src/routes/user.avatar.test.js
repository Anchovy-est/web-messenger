// Integration test for avatar upload against a real Postgres connection
// and the real filesystem (backend/uploads/avatars) — see
// auth.routes.test.js for how to run this.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs/promises');
const path = require('path');
const request = require('supertest');

const { createApp } = require('../app');
const { pool } = require('../config/db');

const app = createApp();

const runId = Date.now();
const createdUsernames = [];
const uploadedAvatarPaths = [];
const UPLOADS_ROOT = path.join(__dirname, '../..');

// Every test that gets back a 200 with an avatarUrl should record it here
// so `after` can delete exactly the files this run created — the actual
// filename includes a server-generated timestamp, not anything the test
// controls, so there's no pattern to glob for after the fact.
function trackAvatarUrl(res) {
  if (res.body?.user?.avatarUrl) {
    uploadedAvatarPaths.push(path.join(UPLOADS_ROOT, res.body.user.avatarUrl));
  }
}

// Minimal but genuinely valid 1x1 images, so tests exercise the same
// magic-byte detection path as a real photo — not just "some bytes".
const VALID_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
);
const VALID_JPEG = Buffer.from(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=',
  'base64'
);
const NOT_AN_IMAGE = Buffer.from('this is definitely not an image');
const OVERSIZED_JPEG = Buffer.concat([
  Buffer.from([0xff, 0xd8, 0xff]),
  Buffer.alloc(6 * 1024 * 1024, 0),
]);

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
  return res.body.accessToken;
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
  // Best-effort: remove exactly the avatar files this run created.
  await Promise.all(uploadedAvatarPaths.map((p) => fs.unlink(p).catch(() => {})));
});

test('POST /users/me/avatar accepts a valid PNG and sets avatarUrl', async () => {
  const accessToken = await registerAndLogin('pngupload');

  const res = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', VALID_PNG, { filename: `${runId}.png`, contentType: 'image/png' });

  assert.equal(res.status, 200);
  assert.match(res.body.user.avatarUrl, /^\/uploads\/avatars\/.+\.png$/);
  trackAvatarUrl(res);
});

test('POST /users/me/avatar accepts a valid JPEG and sets avatarUrl', async () => {
  const accessToken = await registerAndLogin('jpegupload');

  const res = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', VALID_JPEG, { filename: `${runId}.jpg`, contentType: 'image/jpeg' });

  assert.equal(res.status, 200);
  assert.match(res.body.user.avatarUrl, /^\/uploads\/avatars\/.+\.jpg$/);
  trackAvatarUrl(res);
});

test('POST /users/me/avatar rejects a file whose content is not really an image, even with a spoofed image Content-Type', async () => {
  const accessToken = await registerAndLogin('spoofed');

  const res = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', NOT_AN_IMAGE, {
      filename: `${runId}.jpg`,
      contentType: 'image/jpeg', // lies — the bytes aren't a JPEG
    });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_FILE_TYPE');
});

test('POST /users/me/avatar rejects a declared-wrong Content-Type outright', async () => {
  const accessToken = await registerAndLogin('wrongtype');

  const res = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', VALID_PNG, {
      filename: `${runId}.gif`,
      contentType: 'image/gif',
    });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_FILE_TYPE');
});

test('POST /users/me/avatar rejects a file over 5MB', async () => {
  const accessToken = await registerAndLogin('oversized');

  const res = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', OVERSIZED_JPEG, { filename: `${runId}.jpg`, contentType: 'image/jpeg' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_TOO_LARGE');
});

test('POST /users/me/avatar with no file returns 400 FILE_REQUIRED', async () => {
  const accessToken = await registerAndLogin('nofile');

  const res = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`);

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_REQUIRED');
});

test('POST /users/me/avatar requires authentication', async () => {
  const res = await request(app)
    .post('/users/me/avatar')
    .attach('avatar', VALID_PNG, { filename: `${runId}.png`, contentType: 'image/png' });

  assert.equal(res.status, 401);
});

test('replacing an avatar deletes the previous file from disk and serves the new one', async () => {
  const accessToken = await registerAndLogin('replace');

  const first = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', VALID_PNG, { filename: `${runId}-first.png`, contentType: 'image/png' });
  const firstPath = path.join(__dirname, '../..', first.body.user.avatarUrl);
  assert.ok(await fs.stat(firstPath).then(() => true));

  const second = await request(app)
    .post('/users/me/avatar')
    .set('Authorization', `Bearer ${accessToken}`)
    .attach('avatar', VALID_JPEG, { filename: `${runId}-second.jpg`, contentType: 'image/jpeg' });
  assert.notEqual(second.body.user.avatarUrl, first.body.user.avatarUrl);

  // Old file gone...
  await assert.rejects(() => fs.stat(firstPath));
  // ...new file present and served.
  const staticRes = await request(app).get(second.body.user.avatarUrl);
  assert.equal(staticRes.status, 200);

  // Persisted, not just returned in the response — a fresh GET /users/me
  // (the same path session-restore uses) reflects it too.
  const meRes = await request(app)
    .get('/users/me')
    .set('Authorization', `Bearer ${accessToken}`);
  assert.equal(meRes.body.user.avatarUrl, second.body.user.avatarUrl);
  trackAvatarUrl(second); // first's file is already gone; this is the survivor
});
