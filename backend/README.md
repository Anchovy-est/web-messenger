# Backend Developer Guide

Everything you need to work on the `backend/` service independently —
setup, configuration, the database, the API surface, auth, realtime,
deployment, and how to debug it when something goes wrong. The root
[`README.md`](../README.md) covers the project as a whole (the Flutter
client, features, high-level architecture); this file is the detailed,
operational reference for the backend specifically.

**Read this first if you're new here.** It's written so you can go from
zero to a running, testable backend, and then to your first code change,
without needing to ask anyone anything. Where a detail might drift out
of date (an env var, a route), each section says exactly which file is
the real source of truth — trust that file over this document if they
ever disagree.

## Table of Contents

- [Quick Start](#quick-start)
- [What's in `backend/`](#whats-in-backend)
- [Running the Backend and Its Services](#running-the-backend-and-its-services)
- [Environment Variables](#environment-variables)
- [Database: Setup, Migrations, Seeding](#database-setup-migrations-seeding)
- [API Structure and Endpoints](#api-structure-and-endpoints)
- [Authentication and Authorization](#authentication-and-authorization)
- [Realtime: Socket.IO](#realtime-socketio)
- [How the Frontend Talks to This Backend](#how-the-frontend-talks-to-this-backend)
- [API Documentation / Swagger / Postman](#api-documentation--swagger--postman)
- [Logs and Debugging](#logs-and-debugging)
- [How to Add or Modify an Endpoint](#how-to-add-or-modify-an-endpoint)
- [Working with the Database](#working-with-the-database)
- [Testing and Linting](#testing-and-linting)
- [Deploying the Backend (Render)](#deploying-the-backend-render)
- [Checking the Backend in Production](#checking-the-backend-in-production)
- [Common Problems and Troubleshooting](#common-problems-and-troubleshooting)
- [Source of Truth, at a Glance](#source-of-truth-at-a-glance)

## Quick Start

From the repo root:

```bash
docker compose up -d --build
curl http://localhost:3001/health
# {"status":"ok"}
```

That's it — Postgres and the API both start, migrations run
automatically, and the API is reachable on **host port 3001** (see
[Running the Backend](#running-the-backend-and-its-services) for why
3001 and not 3000). No manual `npm install`, no manual database
creation.

## What's in `backend/`

```
backend/
  Dockerfile              Production image: node:20-alpine, npm install,
                           runs docker-entrypoint.sh
  docker-entrypoint.sh    Waits for Postgres, runs migrations, starts the server
  package.json            Scripts and dependencies — see below
  .node-pg-migraterc.json node-pg-migrate config (migrations dir, etc.)
  .env.example            Template for a local .env — copy it, don't commit the copy
  migrations/             Versioned SQL schema changes (node-pg-migrate)
  uploads/                Avatar/media storage (gitignored except .gitkeep)
  src/
    server.js             Entry point: creates the HTTP server + Socket.IO, listens
    app.js                Express app assembly (middleware + route mounting) —
                           separate from server.js so tests can import it without
                           opening a real port
    config/
      env.js               Loads and validates every env var once at startup —
                            THE source of truth for what's configurable and what
                            each variable defaults to
      db.js                PostgreSQL connection pool + query()/withTransaction() helpers
    routes/                Express route tables — one file per resource, plus a
                            same-named `*.test.js` for most of them
    controllers/            Thin HTTP handlers: parse req, call a service, shape the response
    services/               Business logic — this is where rules live, not in controllers
    models/                 SQL query layer — every raw query lives here, nowhere else
    schemas/                Zod request-validation schemas (body/query/params)
    middleware/             authenticate (JWT), validate (schema-driven), upload (multer),
                             rateLimit, errorHandler (central error shape)
    sockets/                Socket.IO auth + event handlers (typing; message events are
                             broadcast from the REST controllers after persisting)
    utils/                  jwt, otp, password hashing, field-level encryption, image
                             type sniffing
```

**Layering convention** (worth knowing before you touch anything):
`route → controller → service → model`. Routes wire up
auth/validation/rate-limiting and point at a controller function.
Controllers are deliberately thin — they read `req`, call one or two
service functions, and shape the HTTP response; no SQL and no business
rules there. Services hold the actual logic (and are what tests and
other services call directly). Models are the only place that runs SQL.
When you're not sure where a piece of new logic belongs, this is the
order to think in.

## Running the Backend and Its Services

**Everything via Docker Compose (recommended)** — from the repo root:

```bash
docker compose up -d --build   # build + start Postgres and the API
docker compose logs -f backend # follow the API's logs
docker compose down            # stop everything
docker compose down -v         # also delete the Postgres volume (fresh DB next time)
```

This starts two services (see [`docker-compose.yml`](../docker-compose.yml)):
- `db` — Postgres 16, with a persistent named volume (`db_data`)
- `backend` — builds `backend/Dockerfile`, waits for `db`'s health check,
  then its entrypoint (`docker-entrypoint.sh`) runs pending migrations
  and starts the server

The API is published on **host port 3001**, mapped to container port
3000 — 3000 itself was found occupied by an unrelated local process
during development on the original machine; the container always
listens on 3000 internally regardless (see the comment in
`docker-compose.yml`). If you change the host port, update anywhere you
point a client at it accordingly.

**Running Node directly, without Docker** (only Postgres needs a real
install or a container for this path):

```bash
# 1. Have a Postgres 16 reachable somewhere, e.g.:
docker run -d --name pg -e POSTGRES_USER=messenger -e POSTGRES_PASSWORD=messenger \
  -e POSTGRES_DB=messenger -p 5432:5432 postgres:16-alpine

# 2. Configure the backend
cd backend
cp .env.example .env
# edit .env — at minimum DATABASE_URL must point at the Postgres from step 1

# 3. Install, migrate, run
npm install
npm run migrate:up
npm run dev          # node --watch, restarts on file changes
# or: npm start       # no watch, closer to production
```

The server logs `mobile-messenger backend listening on port <PORT> (<NODE_ENV>)`
once it's up — that line (from `src/server.js`) is the definitive "it
started" signal in any environment, Docker or not.

## Environment Variables

**Source of truth: [`src/config/env.js`](src/config/env.js)** — every
variable the backend reads is loaded and validated there exactly once
at startup, with defaults where one exists. `.env.example` mirrors it
with comments; copy it to `.env` for local (non-Docker) use — Node's
`dotenv` loads `.env` automatically, and it's gitignored so a real
value never gets committed.

| Variable | Required? | Default | Purpose |
|---|---|---|---|
| `NODE_ENV` | no | `development` | `production` turns on the strict startup checks below; `test` relaxes rate limits and enables test-only secret fallbacks |
| `PORT` | no | `3000` | Port the HTTP server binds to |
| `DATABASE_URL` | **yes, always** | — | Postgres connection string. No fallback in any environment — the process throws immediately if it's missing |
| `JWT_ACCESS_SECRET` | yes in production | test-only fallback under `NODE_ENV=test` | Signs/verifies access tokens |
| `JWT_REFRESH_SECRET` | yes in production | test-only fallback under `NODE_ENV=test` | Signs/verifies refresh tokens |
| `JWT_ACCESS_EXPIRES_IN` | no | `15m` | Access token lifetime ([`ms`](https://www.npmjs.com/package/ms) format) |
| `JWT_REFRESH_EXPIRES_IN` | no | `30d` | Refresh token lifetime |
| `PROFILE_ENCRYPTION_KEY` | yes in production | test-only fallback under `NODE_ENV=test` | Master key for the profile bio field, encrypted at rest (see [`src/utils/fieldCrypto.js`](src/utils/fieldCrypto.js)). Losing/rotating it makes existing encrypted bios permanently unreadable — that's by design, not a bug |
| `CORS_ORIGINS` | yes in production (must be non-empty) | empty = reflect any origin | Comma-separated allow-list of browser origins allowed to call this API — used by both the REST CORS middleware and Socket.IO. Empty is fine for local dev/tests; a real deployment must set it or the process refuses to start |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` / `SMTP_FROM` | no | unset → console-log instead of sending | Outgoing email for verification codes and password resets. See [Logs and Debugging](#logs-and-debugging) for what the console fallback looks like |
| `APP_BASE_URL` | no | `http://localhost:3000` | Informational only right now (no email template currently links to it) |
| `MAX_UPLOAD_BYTES` | no | `26214400` (25MB) | General media-upload cap; avatars have their own, smaller, hardcoded cap (5MB) in [`src/middleware/upload.js`](src/middleware/upload.js) |

**The three production-only checks that will refuse to start the
server** (all in `env.js`, only when `NODE_ENV=production`):
1. `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, or `PROFILE_ENCRYPTION_KEY`
   still equal one of the known placeholder strings shipped in
   `docker-compose.yml` (e.g. `dev_access_secret_change_me`) — generate
   real ones with `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`.
2. `CORS_ORIGINS` is empty.

If you ever see the process exit immediately on boot in a production-like
environment, check these two things first — the thrown error message
names exactly which one failed.

## Database: Setup, Migrations, Seeding

**Setup**: nothing manual — `docker compose up` (or `npm run migrate:up`
if running Node directly) creates every table by replaying
[`migrations/`](migrations/) in order. Migrations are tracked in a
`pgmigrations` table Postgres itself maintains; only ones not yet
recorded there run.

**Inspecting the schema/data directly:**
```bash
docker exec -it mobile-messenger-db-1 psql -U messenger -d messenger
# \dt              list tables
# \d chats         describe one table
# SELECT * FROM users LIMIT 5;
```
(Container name may differ if you renamed the compose project — check
with `docker ps`.)

**Creating a new migration:**
```bash
cd backend
npm run migrate create <descriptive-name>
# edit the generated file in migrations/ — see any existing one for the
# node-pg-migrate API (pgm.createTable, pgm.addColumn, pgm.createIndex, ...)
npm run migrate:up      # apply it locally
```
Restarting the Docker backend also applies any new migration
automatically (that's what `docker-entrypoint.sh` does on every start).

**Rolling back:** `npm run migrate:down` reverts the single most
recent migration — every migration file in this project defines both
`up` and `down`. There's no bulk "roll back to X" script; run it
repeatedly to go back further.

**Seeding**: there is no seed script in this project. The reviewer path
is to actually use the API — register two accounts, verify them (see
[Logs and Debugging](#logs-and-debugging) for finding the verification
code without real email), invite one from the other, and chat. If you
need a repeatable local dataset for development, the natural place to
add one would be a `backend/scripts/seed.js` that calls the same
model/service functions the app itself uses — none currently exists.

**Where the schema itself actually lives**: nowhere as one static file —
the real, current schema is whatever running every file in
`migrations/` in order produces. Read them in filename (timestamp)
order to understand how a table got to its current shape; `psql`'s
`\d <table>` is the fastest way to see its actual current shape.

## API Structure and Endpoints

Every response is JSON. Errors always share one shape (set by
[`src/middleware/errorHandler.js`](src/middleware/errorHandler.js)):
```json
{ "error": { "code": "SOME_CODE", "message": "Human-readable text.", "details": {} } }
```
`details` is only present for validation errors (from
[`src/middleware/validate.js`](src/middleware/validate.js) rejecting a
request against a Zod schema) and holds per-field messages.

🔒 marks a route behind `authenticate` (needs `Authorization: Bearer <accessToken>`).

**Source of truth for the exact routes, validation, and rate limits**:
the route files in [`src/routes/`](src/routes/), each paired with the
schema it validates against in [`src/schemas/`](src/schemas/). The
table below is a snapshot; those files are authoritative if they ever
diverge.

### Health — mounted at `/`

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | Liveness — process is up. No dependency checks. This is `render.yaml`'s `healthCheckPath` |
| GET | `/health/ready` | Readiness — also runs `SELECT 1` against the database |

### Auth — mounted at `/auth`

| Method | Path | Auth | Rate-limited | Body |
|---|---|---|---|---|
| POST | `/auth/register` | — | account-action (8/hr/IP) | `{ username, email, password, displayName? }` |
| POST | `/auth/login` | — | login (10/15min/IP) | `{ email, password }` → `{ user, accessToken, refreshToken }` |
| POST | `/auth/refresh` | — | — | `{ refreshToken }` → new `{ accessToken, refreshToken }` |
| POST | `/auth/logout` | — | — | `{ refreshToken }` — revokes it server-side |
| GET | `/auth/me` | 🔒 | — | → `{ user }` |
| POST | `/auth/verify-email` | — | OTP (10/15min/IP) | `{ email, code }` — 6-digit code |
| POST | `/auth/resend-verification` | — | account-action | `{ email }` |
| POST | `/auth/forgot-password` | — | account-action | `{ email }` |
| POST | `/auth/reset-password` | — | OTP | `{ email, code, newPassword }` |

Password rules (enforced server-side regardless of what the client
sends — see [`src/schemas/auth.schema.js`](src/schemas/auth.schema.js)):
8–72 characters, at least one lowercase, one uppercase, one digit, one
special character.

### Users — mounted at `/users`, all 🔒

| Method | Path | Body / Query | Notes |
|---|---|---|---|
| GET | `/users/search?q=` | — | Username search, excludes yourself |
| GET | `/users/me` | — | Current user's profile |
| PUT | `/users/me` | `{ username, bio }` | Full profile update |
| POST | `/users/me/avatar` | multipart `avatar` file | JPEG/PNG only, 5MB cap, real magic-byte check server-side |
| PUT | `/users/me/public-key` | `{ publicKey }` | Registers this device's E2EE public key (see [Authentication and Authorization](#authentication-and-authorization)) |

### Invitations — mounted at `/invitations`, all 🔒

| Method | Path | Body / Query |
|---|---|---|
| POST | `/invitations` | `{ inviteeId }` — starts a new 1:1 chat invitation |
| GET | `/invitations/received?status=` | optional `pending`/`accepted`/`declined` filter |
| GET | `/invitations/sent?status=` | same filter |
| POST | `/invitations/:id/accept` | creates the chat |
| POST | `/invitations/:id/decline` | — |

### Chats, Messages, Polls — mounted at `/chats`, all 🔒

| Method | Path | Notes |
|---|---|---|
| GET | `/chats?archived=` | List your chats |
| POST | `/chats/groups` | `{ name, participantIds[] }` — create a group chat (2–50 people including you) |
| GET | `/chats/:id` | One chat's detail |
| POST | `/chats/:id/invitations` | Invite one more person into an existing group |
| POST | `/chats/:id/archive` / `/unarchive` | — |
| POST | `/chats/:id/mute` / `/unmute` | Per-user, per-chat — doesn't affect other participants |
| GET | `/chats/:id/messages?limit=&before=` | Cursor-paginated (`before` is a message id) |
| POST | `/chats/:id/messages` | `{ body }` — body is an opaque E2EE ciphertext string; the server never reads plaintext |
| POST | `/chats/:id/messages/media` | multipart `file` + `type` (`image`/`video`/`audio`) — same "opaque ciphertext" rule, 20MB cap |
| PATCH | `/chats/:id/messages/:messageId` | `{ body }` — edit |
| DELETE | `/chats/:id/messages/:messageId` | Soft-delete (tombstone, not physically removed) |
| POST | `/chats/:id/delivered` / `/read` | Marks your own read/delivered receipts |
| POST | `/chats/:id/polls` | `{ question, options[2..10], isAnonymous? }` |
| GET | `/chats/:id/polls/:pollId` | — |
| POST | `/chats/:id/polls/:pollId/vote` | `{ optionId }` |
| DELETE | `/chats/:id/polls/:pollId/vote` | Retract your vote |

## Authentication and Authorization

**Passwords**: bcrypt-hashed (`src/utils/password.js`), never logged or
returned in any response.

**Sessions**: JWT access tokens (15 min default,
`JWT_ACCESS_EXPIRES_IN`) signed/verified in
[`src/utils/jwt.js`](src/utils/jwt.js), carrying just `{ sub: userId }`.
Refresh tokens (30 days default) are longer-lived, stored **hashed** in
the `refresh_tokens` table (never plaintext at rest), and revoked on
logout. `POST /auth/refresh` issues a brand new pair every time
(rotation) — the old refresh token stops working once a new one is
issued.

**The `authenticate` middleware** ([`src/middleware/authenticate.js`](src/middleware/authenticate.js))
is what every 🔒 route above runs through: it reads
`Authorization: Bearer <token>`, verifies it against
`JWT_ACCESS_SECRET`, and sets `req.userId` for the rest of the request.
Any problem with the token — missing, malformed, expired, tampered —
comes back as the same `401 UNAUTHENTICATED`, deliberately not
distinguishing which, so a client (or attacker) gets no extra signal.

**Authorization** (as opposed to authentication) is enforced in the
**service layer**, not the routes: every mutation checks the resource
belongs to (or is visible to) `req.userId` — there is no endpoint that
trusts a client-supplied user id for "who is allowed to do this."
When you add a new mutation, follow this pattern; don't rely on the
route/controller alone.

**End-to-end encryption** (this is what `publicKey` above is for):
each device generates an X25519 identity keypair on first login and
registers only the *public* half via `PUT /users/me/public-key`. Two
devices opening a chat derive a shared AES-256-GCM key via ECDH from
their own private key and the other side's public key — entirely
client-side (`lib/services/encryption_service.dart`). The server only
ever stores and forwards ciphertext (`messages.body` is an opaque
string to it) — there is no key on the server that could decrypt a
message, by design. This is why message/media validation server-side
is limited to shape/size, never content.

## Realtime: Socket.IO

Attached in [`src/sockets/index.js`](src/sockets/index.js). A socket
authenticates during its handshake (`socket.handshake.auth.token`, the
same access token as REST), verified the same way as
`authenticate` middleware. On success it's joined to a room per chat
it's a participant in (`chat:<chatId>`).

**The REST API remains the source of truth** — a message is persisted
via its `POST` before anything is broadcast; Socket.IO only carries the
"a thing happened" push to whoever's currently connected. A client that
was disconnected catches up by re-fetching history over REST on
reconnect, not by replaying missed socket events.

| Direction | Event | Payload | When |
|---|---|---|---|
| server → room | `message:new` | the message | after `POST .../messages` or `.../messages/media` or a poll message persists |
| server → room | `message:edited` | the message | after `PATCH .../messages/:id` |
| server → room | `message:deleted` | the message (tombstoned) | after `DELETE .../messages/:id` |
| server → room | `message:status` | `{ chatId, messageIds, status }` | after `POST .../delivered` or `.../read` |
| server → room | `poll:updated` | `{ chatId, poll }` (never includes the broadcaster's own vote — each client already has that from the REST response) | after a vote is cast/retracted |
| client → room (relayed, not stored) | `typing` | `{ chatId, isTyping }` in; `{ chatId, userId, isTyping }` out | never persisted — no REST equivalent, purely ephemeral |

CORS for the socket server mirrors the REST API's `CORS_ORIGINS` exactly
(same env var, checked in the same file's neighbor,
`src/sockets/index.js`).

## How the Frontend Talks to This Backend

The Flutter client (repo root, `lib/`) is a completely separate
codebase from `backend/` — there's no shared code between them, only an
HTTP/WebSocket contract.

- **Base URL**: baked into the Flutter build at compile time via
  `--dart-define=API_BASE_URL=...` (and optionally `SOCKET_URL`,
  defaulting to the same value) — read in
  [`lib/config/env.dart`](../lib/config/env.dart). There is no runtime
  "change server" setting in the app; a different backend needs a
  rebuild.
- **REST**: [`lib/services/api_client.dart`](../lib/services/api_client.dart)
  wraps one shared `Dio` instance — attaches `Authorization: Bearer
  <accessToken>` to every request, and on a `401` (outside `/auth/*`)
  transparently calls `POST /auth/refresh` once and retries, or signals
  a session-expired callback if that also fails. Every feature's
  `*_repository.dart` file under `lib/features/*/data/` calls this
  client — that's the client-side mirror of the endpoint table above.
- **Realtime**: [`lib/services/socket_service.dart`](../lib/services/socket_service.dart)
  connects to `Env.socketUrl`, sending the current access token in the
  handshake, and re-reads it on every reconnect attempt (so a token
  refreshed mid-session still works). It listens for exactly the events
  in the [Socket.IO table above](#realtime-socketio).
- **CORS is the actual gate** for a browser-based client (the deployed
  web build) — see `CORS_ORIGINS` above. A native mobile build isn't
  subject to CORS at all (that's a browser-only mechanism), so it's
  irrelevant for the Android/iOS client, only for the Flutter **web**
  build on Vercel talking to this backend on Render.

## API Documentation / Swagger / Postman

**None exist in this repository right now** — there is no
`swagger.yaml`/OpenAPI spec and no committed Postman collection. The
[API Structure and Endpoints](#api-structure-and-endpoints) table above,
generated by reading the actual route/schema files, is the closest
thing to one; those source files are the real, always-current
documentation:
- Routes + which middleware/rate-limiter guards each one:
  `src/routes/*.routes.js`
- Exact request-body/query/param shape and validation rules:
  `src/schemas/*.schema.js`
- Response shape: read the corresponding `controllers/*.controller.js`
  function — it's usually a two-line `res.status(...).json({...})`

If you want live, interactive docs, the natural next step would be
adding `swagger-jsdoc`/`swagger-ui-express` (annotate each route) or
hand-writing an OpenAPI YAML and serving it — neither is set up yet, so
budget real time for it rather than expecting a quick toggle.

For manual testing today, the `*.routes.test.js` files under
`src/routes/` double as executable usage examples — each one is a real
HTTP call via `supertest` showing exact request/response shapes for
that route.

## Logs and Debugging

**Local (Docker):**
```bash
docker compose logs -f backend     # follow live
docker logs mobile-messenger-backend-1   # one-off (container name from `docker ps`)
```

**Local (Node directly)**: logs go straight to the terminal you ran
`npm start`/`npm run dev` in.

**Production (Render)**: the service's **Logs** tab in the Render
dashboard — this is the only place to see production `console.log`/
`console.error` output; there's no separate log aggregation configured.

**What to look for:**
- `mobile-messenger backend listening on port ... (production)` — the
  server started successfully. If you never see this line, it crashed
  during startup; the line(s) immediately before it are why (commonly
  one of the [production-only env checks](#environment-variables), or
  a migration failure — see [Common Problems](#common-problems-and-troubleshooting)).
- `[email:dev-mode] To: ... | Subject: ...` followed by the message
  body — this is a verification/reset code that would have been
  emailed, printed here instead because `SMTP_HOST` isn't set. This is
  the normal, intended way to complete registration/reset in local dev
  and in any deployment that hasn't configured SMTP.
- `Unhandled error: ...` / `Uncaught exception: ...` / `Unhandled
  promise rejection: ...` — anything reaching these means a bug wasn't
  turned into a proper `ApiError` somewhere; the client sees a generic
  `500 INTERNAL_ERROR`, and the real cause is only visible in this log
  line. `src/server.js` deliberately exits the process on the latter
  two so a supervisor (Docker's restart policy, Render) restarts it
  clean rather than continuing in a possibly-corrupted state.
- `Push notification failed: ...` — **should never appear**; this was
  removed along with the entire push-notification feature. If you see
  it, you're running stale code — rebuild the image.
- `Socket connected: <id> (user <userId>)` / `Socket disconnected: <id>
  (<reason>)` — one line per realtime connection; useful for confirming
  a client actually reached the socket layer at all.

**Debugging a specific request**: there's no request-id/tracing
middleware in this project. The most direct way to see what a specific
request did is to add a temporary `console.log` in the controller/
service you suspect, or run the relevant `*.test.js` file in isolation:
```bash
node --test src/routes/chat.routes.test.js
```

## How to Add or Modify an Endpoint

Following the [layering convention](#whats-in-backend) above:

1. **Schema** (`src/schemas/<resource>.schema.js`): define/extend a Zod
   schema for the request body, query, or params. This is both
   validation and documentation — someone reading it later learns the
   exact contract.
2. **Route** (`src/routes/<resource>.routes.js`): add the Express
   route, wiring `authenticate` (if it needs a logged-in user),
   `validateBody`/`validateQuery`/`validateParams` with your schema,
   and any rate limiter (`src/middleware/rateLimit.js`) if it's a
   sensitive/account-affecting action — then point it at a controller
   function. Watch route ordering: a literal path (e.g. `/search`) must
   be declared before a `/:id`-shaped one that would otherwise swallow
   it (see the comment in `user.routes.js` for a real example of this).
3. **Controller** (`src/controllers/<resource>.controller.js`): a thin
   function — pull what you need off `req`, call one service function,
   set the status code and `res.json(...)`. Wrap it in `asyncHandler`
   (already the pattern for every existing route) so a thrown/rejected
   error reaches the central error handler instead of crashing the
   process.
4. **Service** (`src/services/<resource>.service.js`): the actual
   logic. Throw `new ApiError(status, code, message)` (from
   `src/middleware/errorHandler.js`) for any expected failure (not
   found, forbidden, conflict, etc.) — the error handler turns that
   into the right HTTP response automatically. Remember the
   authorization rule: check the resource actually belongs to/is
   visible to the caller here, don't assume the route layer did it.
5. **Model** (`src/models/<resource>.model.js`): if you need new SQL,
   add a function here rather than querying from the service directly
   — keeps every raw query in one place per resource.
6. **Migration** (`migrations/`), if the change needs a schema change —
   see [Database Setup, Migrations, Seeding](#database-setup-migrations-seeding).
7. **Test**: add or extend the matching `src/routes/<resource>.routes.test.js`
   (an HTTP-level test via `supertest`, hitting a real test database —
   this project's dominant test style) or a `*.service.test.js`/
   `*.model.test.js` if the logic is more naturally tested in
   isolation. Run `npm test` before considering it done.
8. If the new endpoint should also broadcast over Socket.IO, follow the
   existing pattern in `message.controller.js`/`poll.controller.js`:
   after successfully persisting, `req.app.get('io')?.to(chatRoom(id)).emit(...)`
   — guarded with `if (io)` since `io` is absent when tests exercise
   `createApp()` directly without a real HTTP server.

## Working with the Database

- **Every query goes through `src/config/db.js`**'s `query(text, params)`
  — always parameterized (`$1, $2, ...`), never string-concatenated, to
  avoid SQL injection. Use `withTransaction(async (client) => {...})`
  from the same file for anything that needs more than one statement to
  succeed or fail together (`client.query(...)` inside the callback,
  not the shared `query()` helper, so it runs on the same connection/transaction).
- **Models are the only layer that imports `db.js`.** Services call
  models; they never build SQL themselves. Keep it that way — it's what
  makes it possible to find every query touching a table by grepping
  one directory.
- **Schema changes always go through a migration** — never hand-edit
  the database in a way that isn't captured in `migrations/`, or local,
  test, and production databases will silently drift apart.
- **Local inspection**: `docker exec -it mobile-messenger-db-1 psql -U
  messenger -d messenger` (see [Database Setup](#database-setup-migrations-seeding)
  for common `psql` commands).
- **Tests run against a real Postgres**, not a mock — `npm test` needs
  the `db` service from `docker compose up` already running (see
  [Testing and Linting](#testing-and-linting)).

## Testing and Linting

```bash
cd backend
npm test        # node's built-in test runner; needs a real Postgres reachable
                 # via DATABASE_URL (docker compose's db service, or your own)
npm run lint     # eslint
```

`npm test` sets `NODE_ENV=test` (via `cross-env`, see `package.json`),
which the app itself reacts to in a few places: rate limiters are
skipped entirely (`auth.routes.js`), and the three
[production-only secret checks](#environment-variables) don't apply
(test fallback values are used instead — see `env.js`). Most tests are
HTTP-level (`supertest` against `createApp()`), registering and logging
in real throwaway accounts against the real database, then exercising
the actual routes — this is deliberate: it catches integration bugs a
mocked-database test would miss. A test run creates and cleans up its
own rows (each test file's `after()` hook deletes what it created by a
run-scoped username prefix); it doesn't wipe or reset the whole
database.

Run one file in isolation while iterating:
```bash
DATABASE_URL=postgres://messenger:messenger@localhost:5432/messenger NODE_ENV=test \
  node --test src/routes/chat.routes.test.js
```
(adjust the connection string to wherever your Postgres actually is —
`localhost:5432` if you're running outside Docker and used
`docker-compose.yml`'s port mapping, `db:5432` only from *inside* the
Docker network.)

## Deploying the Backend (Render)

The live source of truth for the deploy configuration is
[`render.yaml`](../render.yaml) at the repo root (a Render
**Blueprint** — provisions the database and the web service together
from one file) plus whatever's filled in by hand in the Render
dashboard's Environment tab for the `sync: false` variables it
deliberately leaves blank (never committed).

1. **Push to GitHub** (or wherever your Render account is connected) —
   Render deploys from a Git remote, not your local disk.
2. In the [Render dashboard](https://dashboard.render.com): **+ New →
   Blueprint**, select the repo. Render parses `render.yaml` and shows
   the resources it's about to create: a Postgres database
   (`web-messenger-db`) and a Docker web service (`web-messenger-backend`,
   built from `backend/Dockerfile`).
   > **In practice this can take two passes.** If the Blueprint sync
   > creates the database but the web service doesn't appear right
   > away, open the **Blueprints** section (not "Ungrouped Services")
   > in the sidebar and look for the blueprint by name — it may be
   > waiting on the `sync: false` values below before it will create
   > the web service. Fill them in and trigger a **Manual sync** if so.
3. **Fill in the `sync: false` environment variables** when prompted
   (see [Environment Variables](#environment-variables) for what each
   does): `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
   `PROFILE_ENCRYPTION_KEY` (three *different* random strings — `node -e
   "console.log(require('crypto').randomBytes(48).toString('hex'))"`),
   and `CORS_ORIGINS` (the deployed web client's exact origin, e.g.
   `https://your-app.vercel.app` — comma-separate more than one).
   `DATABASE_URL` is wired automatically from the Postgres resource;
   you're never asked for it.
4. Once the web service shows **Live**, copy its URL (top of its
   service page, `https://<name>-<random>.onrender.com`) — this is
   `API_BASE_URL` for the Vercel/web-client side (see the root
   [README's Deployment section](../README.md#deployment)).
5. **Uploads persistence**: avatar/message media are written to local
   disk at `/app/uploads`. Render's **free** instance plan doesn't
   support a persistent disk, so uploads are lost on every
   redeploy/restart on that plan — `render.yaml` doesn't declare a
   `disk` block for exactly this reason (declaring one there would make
   the free-plan Blueprint deploy fail outright). Upgrade the service's
   plan and add a `disk` block, or swap in S3-compatible object storage,
   if you need uploads to actually persist.

Every deploy re-runs `docker-entrypoint.sh` — migrations apply
automatically on each deploy, same as local `docker compose up`.

## Checking the Backend in Production

```bash
curl https://<your-service>.onrender.com/health
# {"status":"ok"}
```

That confirms the process is up. To also confirm it can reach its
database:
```bash
curl https://<your-service>.onrender.com/health/ready
# {"status":"ok","database":"connected"}
```

Beyond that, the **Logs** tab in the Render dashboard is the only place
to see production output (see [Logs and Debugging](#logs-and-debugging)
for what to look for) — there's no separate metrics/APM tool wired up.

**A known free-tier quirk**: Render's free instance type spins down
after a period of inactivity, so the first request after a while can
take 30–60 seconds. Separately, free-tier requests can occasionally hit
Render's edge with a `404` and an `x-render-routing: no-server` response
header even when the app itself is healthy and its logs show a clean,
uninterrupted startup — this is edge/routing-layer flakiness on Render's
side, not an application bug. If `/health` is flapping between success
and this specific 404 signature, check the Logs tab for an actual crash
first (there usually isn't one); if the logs are clean, it's this known
platform behavior and typically self-resolves. Persistent flakiness
beyond that is worth a support ticket with Render, or reason enough to
move off the free instance type.

## Common Problems and Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Process exits immediately, no "listening on port" line | Missing `DATABASE_URL`, or (in `NODE_ENV=production`) a placeholder secret / empty `CORS_ORIGINS` | Read the thrown error message — it names the exact variable. See [Environment Variables](#environment-variables) |
| `docker compose up` hangs on "Waiting for database..." | Postgres still starting, or `DATABASE_URL` points at the wrong host (`db` inside Docker's network, not `localhost`) | Give it a few more seconds; if it never clears, check `docker compose logs db` |
| A migration fails on `docker compose up` | A migration file has a bug, or the database already has conflicting state from an older, hand-edited schema | Fix the migration (all pre-release migrations can be safely edited before anyone else has run them); for state drift, `docker compose down -v` for a completely fresh local database |
| `429 RATE_LIMITED` during manual testing | You're hammering `/auth/login`, an OTP endpoint, or another account-action endpoint faster than its limiter allows (see the table in [Authentication and Authorization](#authentication-and-authorization) — well, the limiter values are actually in `src/middleware/rateLimit.js`) | Wait out the window, or run the automated tests instead (`NODE_ENV=test` disables these limiters — see `auth.routes.js`) |
| Verification/reset email "never arrives" | `SMTP_HOST` isn't set — intended behavior, not a bug | Read it from the console/logs instead (see [Logs and Debugging](#logs-and-debugging)), or configure real SMTP env vars |
| `CONFLICT` (409) on an insert you expected to succeed | A unique-constraint violation surfaced generically by `errorHandler.js` (Postgres code `23505`) — e.g. a username or email already taken somewhere that didn't pre-check | Check whether the calling service should have checked uniqueness first and returned a clearer `ApiError`, or if this generic mapping is actually the right behavior here |
| `SERVICE_UNAVAILABLE` (503) | The database is unreachable (`ECONNREFUSED`/`ETIMEDOUT`/connection terminated) — `errorHandler.js` maps this specifically so clients know to retry | Check the database is actually running/reachable from the backend's network |
| Browser console shows a CORS error hitting a deployed backend | `CORS_ORIGINS` on the backend doesn't include the web client's exact origin (scheme + host, no trailing slash) | Update `CORS_ORIGINS` on Render and redeploy — see [Deployment](#deploying-the-backend-render) |
| `flutter run`/web build can't reach the backend at all | Wrong `API_BASE_URL`/`SOCKET_URL` baked into that build, or the backend genuinely isn't reachable from that device (e.g. `10.0.2.2` from a physical device) | See the root README's Android Setup section, and [How the Frontend Talks to This Backend](#how-the-frontend-talks-to-this-backend) |
| Backend answers inconsistently on Render, logs look clean | Free-tier edge/routing flakiness | See [Checking the Backend in Production](#checking-the-backend-in-production) |
| `git push`/deploy fails with a shell script error like `bash\r: No such file or directory` | A `.sh` file picked up Windows CRLF line endings on checkout | The repo's `.gitattributes` (`*.sh text eol=lf`) is meant to prevent this — if you hit it again on a new script, add it there too |

## Source of Truth, at a Glance

| Topic | File(s) |
|---|---|
| Every environment variable, its default, and startup validation | [`src/config/env.js`](src/config/env.js) |
| Local env var template | [`.env.example`](.env.example) |
| Database connection/pool | [`src/config/db.js`](src/config/db.js) |
| Current database schema | replay [`migrations/`](migrations/) in order, or `psql`'s `\d <table>` against a running database |
| Every route + its middleware/rate-limiting | [`src/routes/*.routes.js`](src/routes/) |
| Exact request validation rules | [`src/schemas/*.schema.js`](src/schemas/) |
| Business logic / authorization rules | [`src/services/*.service.js`](src/services/) |
| Error response shape and status-code mapping | [`src/middleware/errorHandler.js`](src/middleware/errorHandler.js) |
| JWT signing/verification | [`src/utils/jwt.js`](src/utils/jwt.js) |
| Socket.IO events and auth | [`src/sockets/index.js`](src/sockets/index.js) |
| Local dev/all-in-one startup | [`../docker-compose.yml`](../docker-compose.yml) |
| Production container build | [`Dockerfile`](Dockerfile), [`docker-entrypoint.sh`](docker-entrypoint.sh) |
| Production deploy topology | [`../render.yaml`](../render.yaml) |
| What the frontend expects from this API | [`../lib/services/api_client.dart`](../lib/services/api_client.dart), [`../lib/services/socket_service.dart`](../lib/services/socket_service.dart), and each `../lib/features/*/data/*_repository.dart` |
| Dependency versions | [`package.json`](package.json) / [`package-lock.json`](package-lock.json) |
