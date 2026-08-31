// Unit-level coverage for the rate limiter itself, isolated from
// auth.routes.js's NODE_ENV=test skip — constructs createRateLimiter
// directly against a throwaway app, so it exercises the same
// middleware real requests would hit in dev/production.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { createRateLimiter } = require('./rateLimit');

function appWithLimiter(max) {
  const app = express();
  app.get(
    '/boom',
    createRateLimiter({ windowMs: 60_000, max, message: 'Too many requests.' }),
    (req, res) => {
      res.status(200).json({ ok: true });
    }
  );
  return app;
}

test('allows requests up to the configured limit', async () => {
  const app = appWithLimiter(3);
  for (let i = 0; i < 3; i += 1) {
    const res = await request(app).get('/boom');
    assert.equal(res.status, 200);
  }
});

test('rejects requests beyond the configured limit with 429', async () => {
  const app = appWithLimiter(3);
  for (let i = 0; i < 3; i += 1) {
    await request(app).get('/boom');
  }

  const res = await request(app).get('/boom');

  assert.equal(res.status, 429);
  assert.equal(res.body.error.code, 'RATE_LIMITED');
  assert.equal(res.body.error.message, 'Too many requests.');
});

test('a 429 response never reaches the wrapped route handler', async () => {
  const app = express();
  let handlerCalls = 0;
  app.get(
    '/boom',
    createRateLimiter({ windowMs: 60_000, max: 1, message: 'Too many requests.' }),
    (req, res) => {
      handlerCalls += 1;
      res.status(200).json({ ok: true });
    }
  );

  await request(app).get('/boom');
  await request(app).get('/boom');

  assert.equal(handlerCalls, 1);
});
