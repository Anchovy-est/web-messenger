// Shared PostgreSQL connection pool. Everything that talks to the
// database goes through `query()` so we have one place to add logging,
// metrics, or a transaction helper later.
const { Pool } = require('pg');
const env = require('./env');

const pool = new Pool({
  connectionString: env.databaseUrl,
  // pg has no default timeout, so without this a request waits
  // forever if the database is unreachable. Failing fast turns it
  // into a normal 503 instead of a hung request.
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  // An idle pooled client errored out, unrelated to any in-flight
  // request — just log it; pg removes the broken client automatically.
  console.error('Unexpected error on idle PostgreSQL client', err);
});

async function query(text, params) {
  return pool.query(text, params);
}

async function getClient() {
  // For callers needing one connection across multiple statements
  // (transactions). Caller is responsible for client.release().
  return pool.connect();
}

async function withTransaction(fn) {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, query, getClient, withTransaction };
