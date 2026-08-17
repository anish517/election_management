#!/bin/bash
set -e

echo "==> 1. Setting up Flutter SDK in Vercel..."
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable flutter
fi

export PATH="$PATH:`pwd`/flutter/bin"
flutter --version

echo "==> 2. Fetching packages..."
cd election_management
flutter pub get

echo "==> 3. Compiling Flutter Web for Production..."
API_URL="${API_BASE_URL:-http://127.0.0.1:8000/v1}"
flutter build web --release --dart-define=API_BASE_URL="$API_URL"

echo "==> 4. Build completed successfully! Output in election_management/build/web."
