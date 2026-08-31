// Unit-level coverage for errorHandler.js's classification branches,
// through a minimal throwaway app — real routes never deliberately
// throw a raw ECONNREFUSED or MulterError, so this is the only way to
// prove each branch produces the response it claims to.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const {
  ApiError,
  asyncHandler,
  notFoundHandler,
  errorHandler,
} = require('./errorHandler');

function appThatThrows(err) {
  const app = express();
  app.get(
    '/boom',
    asyncHandler(async () => {
      throw err;
    })
  );
  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

test('an ApiError is returned with its own status/code/message', async () => {
  const app = appThatThrows(new ApiError(403, 'FORBIDDEN', 'Not your message.'));
  const res = await request(app).get('/boom');

  assert.equal(res.status, 403);
  assert.equal(res.body.error.code, 'FORBIDDEN');
  assert.equal(res.body.error.message, 'Not your message.');
});

test('a Postgres unique-violation becomes a 409 CONFLICT', async () => {
  const pgError = new Error('duplicate key value violates unique constraint');
  pgError.code = '23505';
  const app = appThatThrows(pgError);
  const res = await request(app).get('/boom');

  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, 'CONFLICT');
});

test('a database connection failure (ECONNREFUSED) becomes a 503, not a bare 500', async () => {
  const connError = new Error('connect ECONNREFUSED 127.0.0.1:5432');
  connError.code = 'ECONNREFUSED';
  const app = appThatThrows(connError);
  const res = await request(app).get('/boom');

  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, 'SERVICE_UNAVAILABLE');
  // Tells the client it's worth retrying without leaking the raw
  // connection string/host.
  assert.match(res.body.error.message, /temporarily unavailable/i);
});

test('an unexpectedly dropped database connection also becomes a 503', async () => {
  // pg raises this with no `.code` at all when a live connection is
  // severed mid-query, so the handler also matches on message text.
  const droppedError = new Error('Connection terminated unexpectedly');
  const app = appThatThrows(droppedError);
  const res = await request(app).get('/boom');

  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, 'SERVICE_UNAVAILABLE');
});

test('a MulterError for an oversized file becomes a 400 FILE_TOO_LARGE', async () => {
  const multerError = new Error('File too large');
  multerError.name = 'MulterError';
  multerError.code = 'LIMIT_FILE_SIZE';
  const app = appThatThrows(multerError);
  const res = await request(app).get('/boom');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'FILE_TOO_LARGE');
});

test('an unrecognized error falls back to a generic 500 that hides its details', async () => {
  const app = appThatThrows(new Error('something exploded with a stack trace'));
  const res = await request(app).get('/boom');

  assert.equal(res.status, 500);
  assert.equal(res.body.error.code, 'INTERNAL_ERROR');
  assert.equal(res.body.error.message, 'Something went wrong.');
});

test('a request to an unknown route gets a clean 404, not an unhandled crash', async () => {
  const app = appThatThrows(new Error('unused')); // route never reached
  const res = await request(app).get('/this-route-does-not-exist');

  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, 'NOT_FOUND');
});
