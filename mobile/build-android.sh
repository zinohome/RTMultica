#!/usr/bin/env bash
# RTMultica Native Android Build Script
# Builds a signed (or unsigned) Android APK from upstream's Expo/React Native
# app (apps/mobile), overlaid to point at the self-hosted server.
#
# Mirrors desktop/build.sh: pin upstream tag → overlay config → build →
# restore upstream via git stash on exit.
#
# Prerequisites:
#   - Node 20+, pnpm
#   - Java 17 (JDK) + Android SDK (ANDROID_HOME / ANDROID_SDK_ROOT set)
#   - projects/multica cloned from upstream
#
# Signing (optional — unsigned build if unset):
#   export KEYSTORE_PATH=/abs/path/keystore.jks
#   export KEY_STORE_PASSWORD=... KEY_ALIAS=... KEY_PASSWORD=...
#
# Usage:
#   cd mobile && ./build-android.sh

set -euo pipefail

# Upstream multica tag to build against. Keep in sync with desktop/build.sh.
MULTICA_VERSION="v0.4.3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MULTICA_DIR="$REPO_ROOT/projects/multica"
MOBILE_DIR="$MULTICA_DIR/apps/mobile"
OVERLAY_DIR="$SCRIPT_DIR/overlay/apps/mobile"
DIST_DIR="$SCRIPT_DIR/dist"

# --- Sanity checks ---
if ! command -v pnpm &>/dev/null; then
  echo "Error: pnpm not found. Install via: npm install -g pnpm"
  exit 1
fi
if [ ! -d "$MULTICA_DIR" ]; then
  echo "Error: upstream not found at $MULTICA_DIR"
  echo "Clone it first:"
  echo "  git clone https://github.com/multica-ai/multica.git '$MULTICA_DIR'"
  exit 1
fi

# --- Checkout the target upstream version ---
echo "[build] Checking out upstream multica $MULTICA_VERSION..."
cd "$MULTICA_DIR"
git fetch --tags --quiet
git checkout "$MULTICA_VERSION" --quiet

# --- Apply overlay (saved via git stash, restored on exit) ---
echo "[build] Stashing upstream mobile config..."
git stash push --quiet \
  -- apps/mobile/app.config.ts \
     apps/mobile/.env.production \
  2>/dev/null || true

cleanup() {
  echo ""
  echo "[build] Restoring upstream files..."
  cd "$MULTICA_DIR"
  git stash pop --quiet 2>/dev/null || true
}
trap cleanup EXIT

echo "[build] Applying RTMultica overlay..."
cp "$OVERLAY_DIR/app.config.ts"   "$MOBILE_DIR/app.config.ts"
cp "$OVERLAY_DIR/.env.production"  "$MOBILE_DIR/.env.production"

# EXPO_PUBLIC_* must live in the ENVIRONMENT so Metro inlines them into the
# release bundle — the .env file alone isn't auto-loaded when we invoke expo
# directly (upstream loads it via dotenv-cli in package.json scripts).
set -a
# shellcheck disable=SC1091
source "$OVERLAY_DIR/.env.production"
set +a
export APP_ENV=production
echo "[build] API URL  = $EXPO_PUBLIC_API_URL"
echo "[build] WEB URL  = $EXPO_PUBLIC_WEB_URL"

# --- Install dependencies ---
echo "[build] Installing dependencies (monorepo)..."
cd "$MULTICA_DIR"
# --ignore-scripts avoids upstream apps/web's postinstall (breaks on new Node);
# Expo/RN need no install scripts — prebuild handles native setup.
pnpm install --no-frozen-lockfile --ignore-scripts

# --- Prebuild native Android project ---
echo "[build] Running expo prebuild (android)..."
cd "$MOBILE_DIR"
npx expo prebuild --platform android --clean

# --- Inject release signing + arm64 ABI pin ---
echo "[build] Injecting release signing config..."
node "$SCRIPT_DIR/scripts/inject-android-signing.mjs" "$MOBILE_DIR/android"

# --- Build APK ---
echo "[build] Assembling release APK..."
cd "$MOBILE_DIR/android"
./gradlew assembleRelease --no-daemon

# --- Collect output ---
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/*.apk
APK_OUT="$MOBILE_DIR/android/app/build/outputs/apk/release"
VERSION_CLEAN="${MULTICA_VERSION#v}"
found=0
for apk in "$APK_OUT"/*.apk; do
  [ -f "$apk" ] || continue
  cp "$apk" "$DIST_DIR/multica-rn-${VERSION_CLEAN}-$(basename "$apk")"
  found=1
done

echo ""
if [ "$found" = 1 ]; then
  echo "[build] ✓ Done. Output:"
  ls -lh "$DIST_DIR"/*.apk
else
  echo "[build] ✗ No APK produced — check gradle output above."
  exit 1
fi
