#!/bin/sh
# Runs on every container start: wait for Postgres to accept connections,
# apply any pending migrations, then start the server. This is what makes
# `docker compose up` a true one-command startup — nobody has to
# remember to run migrations by hand.
set -e

echo "Waiting for database..."
until node -e "
  const { Client } = require('pg');
  const c = new Client({ connectionString: process.env.DATABASE_URL });
  c.connect().then(() => c.end()).then(() => process.exit(0)).catch(() => process.exit(1));
"; do
  sleep 1
done
echo "Database is up."

echo "Running migrations..."
npm run migrate:up

echo "Starting server..."
exec node src/server.js
