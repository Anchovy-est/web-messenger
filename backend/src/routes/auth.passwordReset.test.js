// Integration test for password recovery against a real Postgres
// connection — see auth.routes.test.js for how to run this. Same
// email-capture technique as auth.verification.test.js.
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { createApp } = require('../app');
const { pool } = require('../config/db');
const emailService = require('../services/email.service');

const app = createApp();

const runId = Date.now();
const createdUsernames = [];
let capturedEmails = [];
let originalSendEmail;

before(() => {
  originalSendEmail = emailService.sendEmail;
  emailService.sendEmail = async (opts) => {
    capturedEmails.push(opts);
  };
});

after(async () => {
  emailService.sendEmail = originalSendEmail;
  if (createdUsernames.length > 0) {
    await pool.query('DELETE FROM users WHERE username = ANY($1)', [
      createdUsernames,
    ]);
  }
  await pool.end();
});

beforeEach(() => {
  capturedEmails = [];
});

function extractCode(text) {
  const match = text.match(/code is (\d{6})/);
  return match ? match[1] : null;
}

async function registerUser(label) {
  const username = `test_${label}_${runId}`.slice(0, 20);
  createdUsernames.push(username);
  const credentials = {
    username,
    email: `test_${label}_${runId}@example.com`,
    password: 'Password123!',
  };
  await request(app).post('/auth/register').send(credentials);
  capturedEmails = []; // discard the registration verification email
  return credentials;
}

test('POST /auth/forgot-password sends a reset code for a known email', async () => {
  const { email } = await registerUser('forgot');

  const res = await request(app).post('/auth/forgot-password').send({ email });

  assert.equal(res.status, 204);
  assert.equal(capturedEmails.length, 1);
  assert.equal(capturedEmails[0].to, email);
  assert.match(extractCode(capturedEmails[0].text), /^\d{6}$/);
});

test('POST /auth/forgot-password responds 204 for an unknown email without sending anything', async () => {
  const res = await request(app)
    .post('/auth/forgot-password')
    .send({ email: `nobody_${runId}@example.com` });

  assert.equal(res.status, 204);
  assert.equal(capturedEmails.length, 0);
});

test('POST /auth/reset-password rejects a wrong code with 400 INVALID_CODE', async () => {
  const { email } = await registerUser('wrongresetcode');
  await request(app).post('/auth/forgot-password').send({ email });

  const res = await request(app)
    .post('/auth/reset-password')
    .send({ email, code: '000000', newPassword: 'NewPassword123!' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_CODE');
});

test('POST /auth/reset-password accepts the correct code, changes the password, and logs in with the new one', async () => {
  const { email } = await registerUser('resetflow');
  await request(app).post('/auth/forgot-password').send({ email });
  const code = extractCode(capturedEmails[0].text);

  const resetRes = await request(app)
    .post('/auth/reset-password')
    .send({ email, code, newPassword: 'brandNewPassword1!' });
  assert.equal(resetRes.status, 204);

  const oldLoginRes = await request(app)
    .post('/auth/login')
    .send({ email, password: 'Password123!' });
  assert.equal(oldLoginRes.status, 401);

  const newLoginRes = await request(app)
    .post('/auth/login')
    .send({ email, password: 'brandNewPassword1!' });
  assert.equal(newLoginRes.status, 200);
});

test('resetting the password revokes existing sessions', async () => {
  const { email } = await registerUser('resetrevoke');
  const loginRes = await request(app)
    .post('/auth/login')
    .send({ email, password: 'Password123!' });
  const { refreshToken } = loginRes.body;

  await request(app).post('/auth/forgot-password').send({ email });
  const code = extractCode(capturedEmails[0].text);
  await request(app)
    .post('/auth/reset-password')
    .send({ email, code, newPassword: 'anotherNewPassword1!' });

  const refreshRes = await request(app).post('/auth/refresh').send({ refreshToken });
  assert.equal(refreshRes.status, 401);
  assert.equal(refreshRes.body.error.code, 'INVALID_REFRESH_TOKEN');
});

test('a reset code cannot be reused', async () => {
  const { email } = await registerUser('resetreuse');
  await request(app).post('/auth/forgot-password').send({ email });
  const code = extractCode(capturedEmails[0].text);

  const first = await request(app)
    .post('/auth/reset-password')
    .send({ email, code, newPassword: 'firstNewPassword1!' });
  assert.equal(first.status, 204);

  const second = await request(app)
    .post('/auth/reset-password')
    .send({ email, code, newPassword: 'secondNewPassword1!' });
  assert.equal(second.status, 400);
  assert.equal(second.body.error.code, 'INVALID_CODE');
});
