# Mobile Messenger

A secure, real-time mobile messenger with end-to-end encrypted text, image,
video, and voice messages, a Flutter client backed by a Node.js/Express
API and PostgreSQL.

This file covers the project at a high level — what it is, how it's put
together, and how to get it running. For the backend specifically —
environment variables, the database, every API endpoint, authentication,
deployment, debugging, and how to safely add or change an endpoint — see
the **[Backend Developer Guide](backend/README.md)**, which goes much
deeper and is kept as the operational source of truth for `backend/`.

## Table of Contents

- [Project Overview](#project-overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Installation](#installation)
- [Backend Setup](#backend-setup)
- [Database Setup](#database-setup)
- [Android Setup](#android-setup)
- [APK Installation](#apk-installation)
- [Emulator Setup](#emulator-setup)
- [Browser-Based Emulator](#browser-based-emulator)
- [Deployment](#deployment)
- [Usage Guide](#usage-guide)
- [Reviewer Guide](#reviewer-guide)
- [Testing](#testing)
- [Security](#security)
- [Additional Features](#additional-features)
- [Known Limitations](#known-limitations)

## Project Overview

Mobile Messenger is an invitation-based chat app in the shape of a
typical modern messenger: register, verify your email, find people by
username, send an invitation, and once it's accepted, chat- text,
photos, videos, and voice notes, all end-to-end encrypted, delivered in
real time, with typing indicators and read receipts. Chats can be
one-to-one or group (up to 50 people, everyone still invited and
accepting individually - see [Features](#features)).

The backend (`backend/`) is a REST + Socket.IO API on Express and
PostgreSQL, packaged to start with a single `docker compose up`. The client
(root of this repo) is a single Flutter codebase targeting Android (the
platform this project is built and verified for; see
[Known Limitations](#known-limitations) for iOS's status).

## Features

**Messaging**
- Real-time text messaging over Socket.IO, with an optimistic send →
  sent → delivered → read status lifecycle
- Group chats (up to 50 people) alongside one-to-one chats - everyone
  added is invited and has to accept, same as starting a 1:1 chat
- Image and video messages (client-side compressed before upload)
- Voice messages (record, upload, in-app playback)
- Polls: multiple-choice, optionally anonymous, live vote tallies over
  the realtime connection
- Message editing and deletion (soft-deleted as a visible tombstone, not
  silently vanished)
- Typing indicators
- Per-chat mute and archive

**Accounts & social**
- Email/password registration with an email-verification code
- Password strength enforced on registration and reset (8+ characters,
  a lowercase letter, an uppercase letter, a number, a special character),
  both server-side and live in the client as you type
- Password reset by email
- Username search and invitation-based chat creation (no chat starts
  without both sides agreeing to it)
- Editable profile: display name, bio, avatar photo

**Security**
- End-to-end encryption for message bodies and media (see
  [Security](#security))
- JWT access/refresh session model, rate-limited login and OTP endpoints

**UI**
- Light, Dark, and a decorative "Floral" theme (soft botanical
  glassmorphism, fully removed when you switch away from it), switchable
  from the Profile screen
- Consistent loading/empty/error states across every screen, a
  connection-status banner when the realtime socket drops

## Tech Stack

| Layer | Choices |
|---|---|
| Client | Flutter (Dart SDK ^3.12), Riverpod (state), go_router (navigation), Dio (HTTP + auth-refresh interceptor), socket_io_client (realtime) |
| Client crypto | `cryptography` package-  X25519 key exchange, AES-256-GCM |
| Client media | image_picker, flutter_image_compress, video_compress, video_player, record, audioplayers |
| Client storage | flutter_secure_storage (tokens, identity key), path_provider |
| Backend | Node.js ≥20, Express, PostgreSQL 16 |
| Backend realtime | Socket.IO |
| Backend auth | JWT (access + refresh), bcrypt, express-rate-limit |
| Backend media | multer (upload), magic-byte image-type detection for avatars, size caps enforced server-side regardless of what the client claims |
| Infra | Docker Compose (Postgres + API in one command), node-pg-migrate (versioned SQL migrations) |
| Deployment | Vercel (web client), Render (API + Postgres) — see [Deployment](#deployment) |

## Architecture

```
lib/
  config/        Env (API base URL) -overridable via --dart-define
  core/          Theme (light/dark/floral), constants, small utilities
  features/      One folder per feature, each split into data/ (repository)
                 and presentation/ (screens, controllers)
    auth/        Register, login, verify-email, password reset, session
    chats/       Chat list, chat detail, composer, media rendering
    invitations/ Sending/receiving/accepting invitations
    profile/     View/edit profile, avatar, theme picker
    search/      Find users by username
  models/        Plain data classes (User, Chat, Message, ...)
  providers/     App-wide Riverpod providers (wiring services together)
  repositories/  Cross-feature data access
  routing/       go_router route table + auth-gated redirects
  services/      ApiClient (Dio + refresh), SocketService, EncryptionService,
                 SecureStorageService, ...
  widgets/       Shared UI: LoadingView, EmptyStateView, ErrorStateView,
                 UserAvatar, ConnectionBanner, FloralBackground

backend/src/
  config/        Env loading + startup validation (see Security)
  controllers/    Route handlers
  routes/        Express route tables (+ rate limiters wired in per-route)
  services/      Business logic (auth, chat, message, email, ...)
  models/        SQL query layer
  schemas/       Request validation (Zod-style schemas)
  middleware/    Auth guard, upload limits, rate limiting, error handler
  sockets/       Socket.IO auth + event handlers (typing, presence)
  migrations/    node-pg-migrate versioned schema changes, run on startup
```

See the **[Backend Developer Guide](backend/README.md#whats-in-backend)**
for what each backend file actually does and how the layers fit
together (route → controller → service → model).

**End-to-end encryption, in short**: each device generates an X25519
identity keypair on first login and registers only the *public* half with
the server. Opening a chat derives a shared AES-256-GCM key from your
private key and the other participant's public key (classic ECDH) -
the server only ever stores and forwards ciphertext; it has no way to
read message content. See [Security](#security) for the full picture,
including one real bug this exact mechanism surfaced and fixed during
release testing.

**Realtime**: Socket.IO carries new messages, typing events, and
read/delivered receipts to whichever participant is currently connected;
the REST API remains the source of truth (a message is persisted via a
POST before it's pushed), so a disconnected client catches up by simply
re-fetching history on reconnect.

## Installation

You need:
- **Docker** (Docker Desktop on Windows/macOS, or Docker Engine + Compose
  plugin on Linux)-  runs the entire backend, no local Node/Postgres
  install required.
- **Flutter SDK** (3.12+)- to build/run the client. `flutter doctor`
  should report no blocking issues for Android.
- **An Android target**: a physical device (USB or wireless `adb`), an
  Android emulator (Android Studio's AVD manager, or the command-line
  `emulator` binary), or see [Browser-Based Emulator](#browser-based-emulator)
  for a no-local-install option.

```bash
git clone https://github.com/Anchovy-est/web-messenger.git
cd web-messenger
flutter pub get
```

## Backend Setup

One command, from the repo root:

```bash
docker compose up -d --build
```

This builds the backend image, starts PostgreSQL, waits for it to report
healthy, then starts the API server - which runs pending database
migrations itself on every startup. No manual `npm install`, no manual
`createdb`, nothing else to run.

The API listens on **host port 3001** (mapped to container port 3000).
Confirm it's up:

```bash
curl http://localhost:3001/health
# {"status":"ok"}
```

Verification emails (registration codes, password resets) are not sent
anywhere by default- with no `SMTP_HOST` configured, the backend logs
them to its own console instead:

```bash
docker logs -f mobile-messenger-backend-1
# [email:dev-mode] To: someone@example.com | Subject: Verify your email -Mobile Messenger
# Your verification code is 123456. It expires in 30 minutes.
```

This is the intended reviewer path -see the
[Reviewer Guide](#reviewer-guide) for the full walkthrough.

**This is the short version.** For every environment variable, the full
database/migrations workflow, the complete API reference, how
authentication works, how to debug a problem, and how to deploy the
backend on its own — see the
**[Backend Developer Guide](backend/README.md)**.

To stop the stack: `docker compose down` (add `-v` to also drop the
Postgres volume and start completely fresh next time).

## Database Setup

Nothing to do manually - this is handled entirely by
[Backend Setup](#backend-setup): `docker compose up` starts PostgreSQL,
waits for it to report healthy, then applies any pending migration in
`backend/migrations/` before starting the API.

For everything else - inspecting the database, adding a migration,
rolling one back, what "seeding" means for this project (there's no
seed script) - see the Backend Developer Guide's
**[Database section](backend/README.md#database-setup-migrations-seeding)**.

## Android Setup

With the backend running and a device/emulator connected:

```bash
flutter devices          # confirm your target is visible
flutter run               # debug build, hot reload
```

By default the client talks to `http://10.0.2.2:3001` - the Android
**emulator's** special alias for the host machine, matching the backend's
port from [Backend Setup](#backend-setup). This just works for an
emulator. For a **physical device**, `10.0.2.2` means nothing on a real
network, so either:

- forward the device's `localhost:3001` to your machine over USB/wireless
  `adb` and point the client at `localhost`:
  ```bash
  adb reverse tcp:3001 tcp:3001
  flutter run --dart-define=API_BASE_URL=http://localhost:3001
  ```
- or point the client at your machine's real LAN IP instead:
  ```bash
  flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:3001
  ```

## APK Installation

Build a release APK with the same `API_BASE_URL` override your target
device needs (see [Android Setup](#android-setup) for which one applies):

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://localhost:3001
```

The APK is written to
`build/app/outputs/flutter-apk/app-release.apk`. Install it:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**A pre-built copy for the GitHub release**: `releases/mobile-messenger-v1.0.0-release.apk`
(gitignored- large, reproducible build output, not source- see
`.gitignore`) holds the exact APK verified end-to-end for this phase,
built with `--dart-define=API_BASE_URL=http://localhost:3001` (the
physical-device-over-`adb reverse` configuration). It's there purely so
it's easy to locate on disk and attach as a release asset; rebuild with
a different `API_BASE_URL` per [Android Setup](#android-setup) if your
review setup needs a different one (e.g. the emulator's default
`10.0.2.2`, or a real LAN IP).

A release build is signed with the debug key in this project (no
production keystore is configured-  see
[Known Limitations](#known-limitations)), so it installs alongside/over a
debug build of the same app without a signature conflict.

**Note on cleartext HTTP**: this project's backend has no TLS certificate
(it's a local dev/review target, not a real deployment), and Android
blocks plaintext HTTP by default in release builds. `android/app/src/main/res/xml/network_security_config.xml`
carves out a narrow exception for exactly `10.0.2.2`, `localhost`, and
`127.0.0.1` - the loopback-style hosts local review actually uses-  so a
release APK can reach the dev backend at all. This has no effect on and
grants no exception for any real domain.

## Emulator Setup

Using Android Studio: **Tools → Device Manager → Create Device**, pick any
recent phone profile and a system image (an x86_64 image is fastest on
most development machines), then launch it before `flutter run`.

From the command line, once an AVD exists:

```bash
emulator -list-avds
emulator -avd <avd-name>
```

Once it's booted (`adb devices` shows it as `device`, not `offline`),
follow [Android Setup](#android-setup)-  the emulator needs no
`--dart-define` override; `10.0.2.2` is its default and correct.

## Browser-Based Emulator

If you'd rather not install Android Studio or the SDK at all, a service
like [Appetize.io](https://appetize.io) runs an Android emulator entirely
in the browser: create a free account, upload the release APK from
[APK Installation](#apk-installation), and it launches on a cloud device
you interact with through your browser.

One thing this doesn't get you for free: that cloud device has no route
to your `localhost`. Either tunnel your local backend out with something
like `ngrok http 3001` and rebuild the APK with
`--dart-define=API_BASE_URL=<your ngrok https URL>` before uploading it,
or deploy the backend somewhere reachable over the internet and point the
build at that instead. For most reviewers, a local emulator or a
USB-connected physical device (see [Android Setup](#android-setup)) is
the simpler path - this one exists for a machine that genuinely can't run
Android tooling locally.

## Deployment

**Live right now:**

| | URL |
|---|---|
| Web app (Vercel) | https://web-messenger-eight.vercel.app |
| Backend API (Render) | https://web-messenger-backend-eodp.onrender.com |
| Source (GitHub) | https://github.com/Anchovy-est/web-messenger |

The web client (Flutter web) and the backend (Node/Express + Postgres)
deploy to two separate free-tier services: **Vercel** for the static web
build, **Render** for the API + database. Both read from the GitHub repo
above, so a `git push` to `main` is all a redeploy needs once they're
connected (Vercel's Git integration auto-deploys; Render needs a manual
sync unless you've also enabled auto-deploy on it).

### 1. Backend (Render)

The full, detailed walkthrough - including a real quirk in Render's
Blueprint flow you're likely to hit - lives in the
**[Backend Developer Guide](backend/README.md#deploying-the-backend-render)**.
In short:

1. Push to GitHub - Render deploys from a repo it can see, not your
   local disk.
2. In the [Render dashboard](https://dashboard.render.com), **+ New →
   Blueprint**, point it at the repo. Render reads
   [`render.yaml`](render.yaml) and provisions a Docker web service
   (`backend/Dockerfile`) plus a managed Postgres database.
3. Fill in the `sync: false` secrets it prompts for
   (`JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `PROFILE_ENCRYPTION_KEY`,
   `CORS_ORIGINS`) - see the backend guide for exactly what each does
   and how to generate them.
4. Once the service shows **Live**, `https://<your-service>.onrender.com/health`
   should return `{"status":"ok"}`. That URL is `API_BASE_URL` for the
   web client below.

**Uploads note:** avatar images and message media are written to a
local disk at `/app/uploads`, which Render's **free** instance plan
doesn't persist - uploads are lost on every redeploy/restart on that
plan. Upgrade the service's plan and add a `disk` block to
`render.yaml`, or swap in S3-compatible object storage, if you need
uploads to survive a redeploy.

### 2. Web client (Vercel)

1. In the [Vercel dashboard](https://vercel.com), **Add New -> Project**,
   import the same repo. Vercel reads [`vercel.json`](vercel.json) at the
   repo root, which runs [`scripts/vercel-build.sh`](scripts/vercel-build.sh)
   - this installs the Flutter SDK during the build (Vercel's build
   image doesn't ship one) and runs `flutter build web --release`, so
   there's nothing to configure in the Vercel UI's framework/build
   settings themselves.
2. Before the first deploy, add two **Environment Variables** in the
   Vercel project settings:
   - `API_BASE_URL` - the Render backend URL from step 1
     (`https://<your-service>.onrender.com`).
   - `SOCKET_URL` - optional; defaults to `API_BASE_URL` if unset (the
     backend serves both REST and Socket.IO from the same origin).

   These are read by `scripts/vercel-build.sh` and baked into the build
   via `--dart-define`, the exact mechanism `lib/config/env.dart`
   already reads at runtime - no client code changes needed.
3. Deploy. Vercel gives you a URL like
   `https://your-app.vercel.app` - that's the whole web app, live.
   Redeploying after an env var change: `vercel --prod` from the repo
   root (with the [Vercel CLI](https://vercel.com/docs/cli) installed
   and `vercel link` run once), or trigger it from the dashboard.

   **If you fork/copy this repo on Windows**, make sure `scripts/vercel-build.sh`
   keeps LF line endings, not CRLF - Vercel's Linux build environment
   fails on a CRLF shebang line with a cryptic `bash\r: No such file or
   directory` error. The repo's [`.gitattributes`](.gitattributes)
   (`*.sh text eol=lf`) forces this on checkout; keep that file if you
   add more shell scripts.

### 3. Close the loop: lock down CORS

Back in Render, set the `CORS_ORIGINS` env var (left blank in step 1) to
your Vercel URL from step 2, then redeploy the backend (Render redeploys
automatically on an env var change, or trigger one manually). This is
what actually restricts the API to your deployed frontend instead of
reflecting any origin - see `backend/src/app.js` and
`backend/src/sockets/index.js`. Verify it worked: opening the Vercel app
and using it (register, log in, send a message) should all work
normally; a request to the API from a *different* origin (e.g. the
browser console on some unrelated page) should be blocked by CORS.

Multiple origins (e.g. a Vercel preview-deployment URL alongside the
production one) are supported - comma-separate them:
`CORS_ORIGINS=https://your-app.vercel.app,https://your-app-git-main.vercel.app`.

## Usage Guide

1. **Register** with an email, username, and password.
2. **Verify your email**- the 6-digit code is either emailed to you (if
   SMTP is configured) or printed to `docker logs
   mobile-messenger-backend-1` (see [Backend Setup](#backend-setup)).
   Unverified accounts can still use the app; a banner just reminds you
   to verify.
3. **Find someone**: tap Search, look up their username, tap Invite.
4. **Accept an invitation**: the other person opens Invitations (mail
   icon) and accepts - this is what actually creates the chat; nobody
   can message you without your acceptance.
5. **Chat**: text, the paperclip for photos/videos, the mic for a voice
   message. Long-press your own message to edit or delete it. Tap the
   bell in a chat's app bar to mute it; swipe/archive from the chat list
   to move it to the Archived tab.
6. **Profile**: tap the person icon to change your display name, bio, or
   avatar, and to switch between Light, Dark, and Floral themes.

## Reviewer Guide

The fastest path to a working, testable app, start to finish:

```bash
# 1. Backend - one command, from the repo root
docker compose up -d --build
curl http://localhost:3001/health   # expect {"status":"ok"}

# 2. Client dependencies
flutter pub get
```

**Choose one device path:**

- **Emulator** (simplest-  no extra flags needed):
  ```bash
  emulator -avd <your-avd-name>          # or launch from Android Studio
  flutter run                             # default API_BASE_URL already matches
  ```
- **Physical device over USB/wireless adb**:
  ```bash
  adb reverse tcp:3001 tcp:3001
  flutter run --dart-define=API_BASE_URL=http://localhost:3001
  ```

**Try the whole flow** (two accounts, since nobody can message themselves):

1. Register account **A** in the running app. Get its verification code
   with `docker logs mobile-messenger-backend-1 | grep "verification code"`
   (the most recent match is yours), and enter it on the Verify Email
   screen.
2. Register account **B** the same way - either on a second
   device/emulator, or by logging out of A and back in as B on the same
   one.
3. As B: Search for A's username → Invite.
4. As A: Invitations → Accept. The chat now appears on both sides.
5. Send a text message, then try an image/voice message, editing a
   message, and archiving/muting the chat.

**If a release APK is what's being reviewed** instead of `flutter run`,
build it per [APK Installation](#apk-installation) with the
`API_BASE_URL` matching whichever device path you chose above, then
`adb install -r` it and repeat the same flow - this is exactly the path
used to verify the release build during development (see
[Known Limitations](#known-limitations) for one bug that verification
found and fixed).

**Inspecting the database directly**, if useful:
```bash
docker exec -it mobile-messenger-db-1 psql -U messenger -d messenger
```

## Testing

**Client** (from the repo root):
```bash
flutter analyze                          # static analysis, zero issues expected
dart format --set-exit-if-changed lib test  # formatting check
flutter test                             # full widget/unit test suite
```

**Backend** (from `backend/`):
```bash
npm test        # runs against the real Postgres in docker-compose -
                 # start the backend stack first
npm run lint     # eslint
```

Both suites are meant to be run with the Docker backend already up, since
several backend tests exercise real HTTP/Socket.IO round-trips rather
than mocking the database. See the Backend Developer Guide's
**[Testing and Linting section](backend/README.md#testing-and-linting)**
for what `NODE_ENV=test` changes (rate limits, secret fallbacks) and how
to run a single test file.

## Security

- **Passwords**: bcrypt-hashed, never logged or returned by any API
  response.
- **Sessions**: short-lived JWT access tokens (15 min) plus longer-lived
  refresh tokens (30 days), refreshed transparently by the client's HTTP
  interceptor; refresh tokens are stored hashed server-side and revoked
  on logout.
- **Transport**: the client only ever accepts plaintext HTTP to the
  handful of loopback-style dev hosts described in
  [APK Installation](#apk-installation) -everywhere else, Android's
  default TLS-only behavior is untouched.
- **End-to-end encryption**: message bodies and media are encrypted on
  the sender's device with a key derived from an X25519 ECDH exchange
  (see [Architecture](#architecture)) before they ever reach the network;
  the server stores and relays ciphertext it cannot read. Each device's
  private key never leaves it (`flutter_secure_storage`).
- **Rate limiting**: login, OTP verification (email verify, password
  reset), and other account-sensitive endpoints are rate-limited
  per-IP (`backend/src/middleware/rateLimit.js`)-specifically added
  after a security review found the OTP endpoints were brute-forceable
  without it.
- **Authorization**: every message/profile/chat mutation is checked
  server-side against the authenticated user's own id- there is no
  endpoint that trusts a client-supplied user id for who's allowed to
  act on something.
- **File uploads**: both file size (5MB avatars, 20MB message media) and
  MIME type are validated server-side (`backend/src/middleware/upload.js`),
  never trusted from client-reported metadata alone.
- **Secrets**: `docker-compose.yml` ships obvious placeholder defaults
  (`dev_access_secret_change_me` and similar) for local use only; the
  backend refuses to start in `NODE_ENV=production` if any of the three
  secrets still match a known placeholder value
  (`backend/src/config/env.js`). No real secret is committed to this
  repository.
- **CORS**: wide open (reflects any origin) in local dev and in the test
  suite, since neither has a meaningful origin to restrict to. A
  production deployment must set `CORS_ORIGINS` to the deployed web
  client's exact origin(s) - the backend refuses to start in
  `NODE_ENV=production` without it set at all (`backend/src/config/env.js`,
  `backend/src/app.js`, `backend/src/sockets/index.js`). See
  [Deployment](#deployment).
- **Password strength**: enforced identically in two places-
  `backend/src/schemas/auth.schema.js` (the actual gate: registration and
  password reset are rejected server-side regardless of what the client
  sends) and `lib/core/utils/password_rules.dart` (the client's own
  validator plus a live, as-you-type checklist-
  `lib/widgets/password_strength_checklist.dart`). A full requirements
  audit against this app's spec found the original version of both only
  checked length and "a letter and a digit", never actually verifying
  uppercase, lowercase, or a special character despite claiming to-
  fixed on both sides, with new test coverage (a dedicated test per
  missing character class) pinning it down against ever silently
  regressing back to the looser check.
- **A real bug this caught**: release-mode testing surfaced a case where
  a failed one-time key-registration network call (during a device's
  first login) would silently and *permanently* leave that account
  unable to derive chat encryption keys with anyone, since nothing ever
  retried the upload once a local key already existed. Fixed in
  `SessionController._ensureIdentityKeyPair` to retry registration on
  every login/restore until the server actually has the key on file -
  exactly the kind of thing end-to-end release testing, not just unit
  tests, is for.
- **Error resilience**: a widget that throws while building, laying out,
  or painting shows a small, calm fallback (`lib/widgets/app_error_fallback.dart`,
  wired up via `ErrorWidget.builder` in `main.dart`) instead of Flutter's
  own error widget (blank in release builds)- Flutter already scopes
  the failure to just that one widget, so the rest of the screen keeps
  working. `PlatformDispatcher.instance.onError` catches whatever else
  reaches the platform layer uncaught, logging it instead of crashing
  the app outright. Every *expected* failure (a failed API call, a
  socket drop) already has its own handling- a retry button via
  `ErrorStateView`, the `ConnectionBanner`, a failed-message "tap to
  retry"- this is the backstop for the unexpected kind.

## Additional Features

- **Floral theme**: a third, purely decorative theme option (alongside
  Light/Dark) built from a curated pastel palette and a single recolored
  SVG flower asset scattered subtly behind the UI-  see
  `lib/core/theme/floral_palette.dart` and `lib/widgets/floral_background.dart`.
- **Client-side media compression**: images and videos are compressed on
  the device before encryption/upload, so large phone-camera media
  doesn't routinely hit the 20MB server-side cap.

## Known Limitations

- **Android only, verified**: the codebase includes an `ios/` project
  scaffold, but this project has been built, run, and verified only for
  Android.
- **No production keystore**: release APKs are signed with the default
  debug key (see [APK Installation](#apk-installation)); a real release
  to a store would need its own signing key, which is out of scope for a
  local/reviewer build.
- **OTP brute-force mitigation is per-IP, not per-account**: the rate
  limiter added during the security review (see [Security](#security))
  meaningfully raises the bar but doesn't fully stop a distributed
  (many-IP) brute-force attempt, a deliberate, documented trade-off
  against over-engineering a local/review-scale project.
- **Email is console-logged, not sent, unless you configure SMTP**, by
  design for local review (see [Backend Setup](#backend-setup)), not
  something to rely on for a real deployment as-is.
- **Uploaded media doesn't persist across a Render redeploy on the free
  plan**, and the free instance type spins down when idle and can
  answer inconsistently for a short window after - see the [Backend
  Developer Guide](backend/README.md#checking-the-backend-in-production)
  for what that looks like and why it isn't an application bug.
