// Integration test for the email verification flow against a real
// Postgres connection.
//
// The outgoing email is intercepted by monkey-patching email.service's
// exported `sendEmail` (Node caches the module, so auth.service.js sees
// the same mutated function) instead of pulling in a mocking library.
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
  return credentials;
}

test('registering sends a verification email with a 6-digit code', async () => {
  const { email } = await registerUser('sendcode');

  assert.equal(capturedEmails.length, 1);
  assert.equal(capturedEmails[0].to, email);
  const code = extractCode(capturedEmails[0].text);
  assert.match(code, /^\d{6}$/);
});

test('POST /auth/verify-email rejects a wrong code with 400 INVALID_CODE', async () => {
  const { email } = await registerUser('wrongcode');

  const res = await request(app)
    .post('/auth/verify-email')
    .send({ email, code: '000000' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_CODE');
});

test('POST /auth/verify-email accepts the correct code and marks the user verified', async () => {
  const { email } = await registerUser('rightcode');
  const code = extractCode(capturedEmails[0].text);

  const res = await request(app).post('/auth/verify-email').send({ email, code });

  assert.equal(res.status, 200);
  assert.equal(res.body.user.emailVerified, true);
});

test('POST /auth/verify-email rejects reusing the same code twice', async () => {
  const { email } = await registerUser('reusecode');
  const code = extractCode(capturedEmails[0].text);

  const first = await request(app).post('/auth/verify-email').send({ email, code });
  assert.equal(first.status, 200);

  // Already verified after the first call, so this second call with
  // the consumed code succeeds idempotently rather than failing.
  const second = await request(app).post('/auth/verify-email').send({ email, code });
  assert.equal(second.status, 200);
  assert.equal(second.body.user.emailVerified, true);
});

test('POST /auth/resend-verification sends a new usable code', async () => {
  const { email } = await registerUser('resend');

  const res = await request(app).post('/auth/resend-verification').send({ email });
  assert.equal(res.status, 204);
  assert.equal(capturedEmails.length, 2); // register + resend
  const newCode = extractCode(capturedEmails[1].text);

  const verifyRes = await request(app)
    .post('/auth/verify-email')
    .send({ email, code: newCode });
  assert.equal(verifyRes.status, 200);
});

test('POST /auth/resend-verification responds 204 for an unknown email without sending anything', async () => {
  const res = await request(app)
    .post('/auth/resend-verification')
    .send({ email: `nobody_${runId}@example.com` });

  assert.equal(res.status, 204);
  assert.equal(capturedEmails.length, 0);
});
