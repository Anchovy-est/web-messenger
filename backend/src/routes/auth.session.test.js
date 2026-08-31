// Integration test for login/session lifecycle against a real Postgres
// connection — see auth.routes.test.js for how to run this (docker-compose
// `db` service must be up).
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
  return { credentials, ...res.body };
}

after(async () => {
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

test('POST /auth/login rejects wrong password with 401 INVALID_CREDENTIALS', async () => {
  const { credentials } = await registerAndLogin('wrongpw');

  const res = await request(app)
    .post('/auth/login')
    .send({ email: credentials.email, password: 'totallyWrong1' });

  assert.equal(res.status, 401);
  assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
});

test('POST /auth/login rejects an unknown email with the same error as wrong password', async () => {
  const res = await request(app)
    .post('/auth/login')
    .send({ email: `nobody_${runId}@example.com`, password: 'whatever123' });

  assert.equal(res.status, 401);
  assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
});

test('POST /auth/login succeeds and GET /auth/me returns the same user with a valid token', async () => {
  const { accessToken, user } = await registerAndLogin('login');
  assert.ok(accessToken);

  const res = await request(app)
    .get('/auth/me')
    .set('Authorization', `Bearer ${accessToken}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.user.id, user.id);
});

test('GET /auth/me rejects requests with no token', async () => {
  const res = await request(app).get('/auth/me');
  assert.equal(res.status, 401);
  assert.equal(res.body.error.code, 'UNAUTHENTICATED');
});

test('GET /auth/me rejects a garbage token', async () => {
  const res = await request(app)
    .get('/auth/me')
    .set('Authorization', 'Bearer not-a-real-token');
  assert.equal(res.status, 401);
});

test('POST /auth/refresh rotates the refresh token and rejects reuse of the old one', async () => {
  const { refreshToken } = await registerAndLogin('refresh');

  const refreshRes = await request(app).post('/auth/refresh').send({ refreshToken });
  assert.equal(refreshRes.status, 200);
  assert.ok(refreshRes.body.accessToken);
  assert.ok(refreshRes.body.refreshToken);
  assert.notEqual(refreshRes.body.refreshToken, refreshToken);

  const reuseRes = await request(app).post('/auth/refresh').send({ refreshToken });
  assert.equal(reuseRes.status, 401);
  assert.equal(reuseRes.body.error.code, 'INVALID_REFRESH_TOKEN');
});

test('POST /auth/logout revokes the refresh token so it can no longer be used', async () => {
  const { refreshToken } = await registerAndLogin('logout');

  const logoutRes = await request(app).post('/auth/logout').send({ refreshToken });
  assert.equal(logoutRes.status, 204);

  const refreshRes = await request(app).post('/auth/refresh').send({ refreshToken });
  assert.equal(refreshRes.status, 401);
  assert.equal(refreshRes.body.error.code, 'INVALID_REFRESH_TOKEN');
});

// Nothing in this API distinguishes clients by platform — independence
// comes from `login` always issuing a brand new refresh token instead
// of replacing an existing session, and `logout` revoking only the
// token it was handed. Regression guard: two logins for the same
// account must behave as two fully separate sessions, both ways.
test('logging in twice for the same account creates two independent sessions — logging out one does not affect the other', async () => {
  const username = `test_multisession_${runId}`.slice(0, 20);
  createdUsernames.push(username);
  const credentials = {
    username,
    email: `test_multisession_${runId}@example.com`,
    password: 'Password123!',
  };
  await request(app).post('/auth/register').send(credentials);

  const mobileLogin = await request(app).post('/auth/login').send({
    email: credentials.email,
    password: credentials.password,
  });
  const webLogin = await request(app).post('/auth/login').send({
    email: credentials.email,
    password: credentials.password,
  });
  assert.notEqual(
    mobileLogin.body.refreshToken,
    webLogin.body.refreshToken,
    'each login must mint its own refresh token, not share/replace one'
  );

  // Both sessions independently authenticated before either logs out.
  const mobileMeBefore = await request(app)
    .get('/auth/me')
    .set('Authorization', `Bearer ${mobileLogin.body.accessToken}`);
  const webMeBefore = await request(app)
    .get('/auth/me')
    .set('Authorization', `Bearer ${webLogin.body.accessToken}`);
  assert.equal(mobileMeBefore.status, 200);
  assert.equal(webMeBefore.status, 200);

  // Logging out Web must not touch Mobile's session.
  const webLogoutRes = await request(app)
    .post('/auth/logout')
    .send({ refreshToken: webLogin.body.refreshToken });
  assert.equal(webLogoutRes.status, 204);

  const mobileRefreshAfterWebLogout = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: mobileLogin.body.refreshToken });
  assert.equal(
    mobileRefreshAfterWebLogout.status,
    200,
    "Mobile's session must survive a Web logout"
  );

  const webRefreshAfterWebLogout = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: webLogin.body.refreshToken });
  assert.equal(webRefreshAfterWebLogout.status, 401);
  assert.equal(webRefreshAfterWebLogout.body.error.code, 'INVALID_REFRESH_TOKEN');

  // And the reverse: logging out Mobile must not touch a fresh Web
  // session.
  const web2Login = await request(app).post('/auth/login').send({
    email: credentials.email,
    password: credentials.password,
  });
  const mobileLogoutRes = await request(app)
    .post('/auth/logout')
    .send({ refreshToken: mobileRefreshAfterWebLogout.body.refreshToken });
  assert.equal(mobileLogoutRes.status, 204);

  const web2RefreshAfterMobileLogout = await request(app)
    .post('/auth/refresh')
    .send({ refreshToken: web2Login.body.refreshToken });
  assert.equal(
    web2RefreshAfterMobileLogout.status,
    200,
    "Web's session must survive a Mobile logout"
  );
});
