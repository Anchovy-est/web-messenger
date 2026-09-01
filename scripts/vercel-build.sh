#!/usr/bin/env bash
# Builds the Flutter web client for Vercel. Vercel's build image has no
# Flutter SDK, so this installs one (stable channel — matches the
# `sdk: ^3.12.2` constraint in pubspec.yaml) before building, the same
# way you'd set up a fresh machine locally.
#
# API_BASE_URL / SOCKET_URL come from Vercel project environment
# variables (Project Settings → Environment Variables) — set them to
# the deployed Render backend's URL, e.g.
# https://web-messenger-backend.onrender.com. See README.md's
# Deployment section for the full click-through steps. Baked in via
# --dart-define, the exact mechanism lib/config/env.dart already reads
# — no client code changes needed for this to work.
set -euo pipefail

if [ -z "${API_BASE_URL:-}" ]; then
  echo "API_BASE_URL is not set — configure it in the Vercel project's" >&2
  echo "Environment Variables before deploying (see README.md)." >&2
  exit 1
fi

echo "Installing Flutter (stable)..."
git clone https://github.com/flutter/flutter.git --branch stable --depth 1 "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter pub get

echo "Building web release..."
flutter build web --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=SOCKET_URL="${SOCKET_URL:-$API_BASE_URL}"
