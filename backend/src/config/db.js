// Shared PostgreSQL connection pool. Everything that talks to the
// database goes through `query()` so we have one place to add logging,
// metrics, or a transaction helper later.
const { Pool } = require('pg');
const env = require('./env');

const pool = new Pool({
  connectionString: env.databaseUrl,
  // Without this, a request that needs a connection while the database
  // is unreachable (down, network partition) waits forever — pg's
  // default is no timeout at all — which looks like a hung request to
  // the client, not an error. Failing fast lets it surface as a normal
  // 503 through errorHandler.js instead.
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  // A background client (idle in the pool) errored out. This does not
  // belong to any in-flight request, so just log it — pg will remove the
  // broken client from the pool automatically.
  console.error('Unexpected error on idle PostgreSQL client', err);
});

async function query(text, params) {
  return pool.query(text, params);
}

async function getClient() {
  // For callers that need a single connection across multiple statements
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
