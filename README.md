# Mobile Messenger

A secure, real-time mobile messenger with end-to-end encrypted text, image,
video, and voice messages, a Flutter client backed by a Node.js/Express
API and PostgreSQL.

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
- [Usage Guide](#usage-guide)
- [Reviewer Guide](#reviewer-guide)
- [Testing](#testing)
- [Security](#security)
- [Additional Features](#additional-features)
- [Known Limitations](#known-limitations)

## Project Overview

Mobile Messenger is a two-party chat app in the shape of a typical modern
messenger: register, verify your email, find people by username, send an
invitation, and once it's accepted, chat- text, photos, videos, and voice
notes, all end-to-end encrypted, delivered in real time, with typing
indicators and read receipts.

The backend (`backend/`) is a REST + Socket.IO API on Express and
PostgreSQL, packaged to start with a single `docker compose up`. The client
(root of this repo) is a single Flutter codebase targeting Android (the
platform this project is built and verified for; see
[Known Limitations](#known-limitations) for iOS's status).

## Features

**Messaging**
- Real-time text messaging over Socket.IO, with an optimistic send →
  sent → delivered → read status lifecycle
- Image and video messages (client-side compressed before upload)
- Voice messages (record, upload, in-app playback)
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
- Push notifications (Firebase Cloud Messaging), off by default until a
  Firebase project is configured - see
  [Additional Features](#additional-features)

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
| Client push | firebase_messaging, flutter_local_notifications |
| Backend | Node.js ≥20, Express, PostgreSQL 16 |
| Backend realtime | Socket.IO |
| Backend auth | JWT (access + refresh), bcrypt, express-rate-limit |
| Backend media | multer (upload), sharp/ffmpeg-adjacent server-side validation (type/size re-enforced server-side, never trusted from the client) |
| Infra | Docker Compose (Postgres + API in one command), node-pg-migrate (versioned SQL migrations) |

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
                 SecureStorageService, PushNotificationService, ...
  widgets/       Shared UI: LoadingView, EmptyStateView, ErrorStateView,
                 UserAvatar, ConnectionBanner, FloralBackground

backend/src/
  config/        Env loading + startup validation (see Security)
  controllers/    Route handlers
  routes/        Express route tables (+ rate limiters wired in per-route)
  services/      Business logic (auth, chat, message, email, push, ...)
  models/        SQL query layer
  schemas/       Request validation (Zod-style schemas)
  middleware/    Auth guard, upload limits, rate limiting, error handler
  sockets/       Socket.IO auth + event handlers (typing, presence)
  migrations/    node-pg-migrate versioned schema changes, run on startup
```

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
git clone <this-repo-url>
cd mobile-messenger
flutter pub get
```

## Backend Setup

One command, from the repo root:

```bash
docker compose up -d --build
```

This builds the backend image, starts PostgreSQL, waits for it to report
healthy, then starts the API server - which runs pending database
migrations itself on every startup (see [Database Setup](#database-setup)).
No manual `npm install`, no manual `createdb`, nothing else to run.

The API listens on **host port 3001** (mapped to container port 3000 -
see the comment in `docker-compose.yml` for why 3000 itself is avoided).
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
[Reviewer Guide](#reviewer-guide) for the full walkthrough. To send real
email instead, set `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER`/`SMTP_PASS`/
`SMTP_FROM` (as environment variables, e.g. in a `.env` file
docker-compose picks up) before starting the stack.

To stop the stack: `docker compose down` (add `-v` to also drop the
Postgres volume and start completely fresh next time).

## Database Setup

Nothing to do manually - this is handled entirely by
[Backend Setup](#backend-setup). For reference, what happens automatically
on every `docker compose up`:

1. The `db` service starts PostgreSQL 16 with a persistent named volume
   (`db_data`) - your data survives container restarts.
2. The `backend` service waits for Postgres's health check, then its
   entrypoint runs `node-pg-migrate up`, applying any migration in
   `backend/migrations/` not yet recorded in the `pgmigrations` table.
3. The server starts once migrations succeed.

To inspect the database directly:

```bash
docker exec -it mobile-messenger-db-1 psql -U messenger -d messenger
```

To add a new migration during development: `cd backend && npm run migrate
create <name>`, edit the generated file, then restart the backend (or run
`npm run migrate:up` inside the container) to apply it.

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
than mocking the database.

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

- **Push notifications**: integrated via Firebase Cloud Messaging, but
  inert until you provide your own Firebase project - drop a
  `firebase-service-account.json` into `backend/secrets/` (bind-mounted
  read-only into the container per `docker-compose.yml`) and configure
  the client's own Firebase config. Without it, the app works completely
  normally- every push-related call degrades to a silent no-op instead
  of throwing.
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
- **Push notifications need your own Firebase project**, not configured
  by default (see [Additional Features](#additional-features)).
- **OTP brute-force mitigation is per-IP, not per-account**: the rate
  limiter added during the security review (see [Security](#security))
  meaningfully raises the bar but doesn't fully stop a distributed
  (many-IP) brute-force attempt, a deliberate, documented trade-off
  against over-engineering a local/review-scale project.
- **No group chats**: every chat is strictly two-party, by invitation.
- **Email is console-logged, not sent, unless you configure SMTP**, by
  design for local review (see [Backend Setup](#backend-setup)), not
  something to rely on for a real deployment as-is.
