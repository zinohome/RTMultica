#!/usr/bin/env bash
# RTMultica Desktop Build Script
# Builds unsigned mac arm64 + x64 DMGs pointing to the self-hosted server.
#
# Prerequisites (run on macOS):
#   - Go (for bundling the multica CLI)
#   - Node.js 22 + pnpm
#   - projects/multica cloned from upstream
#
# Usage:
#   cd desktop && ./build.sh
#   cd desktop && ./build.sh --arm64-only
#   cd desktop && ./build.sh --x64-only

set -euo pipefail

# Upstream multica version to build against. Update this on each release.
MULTICA_VERSION="v0.4.11"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MULTICA_DIR="$REPO_ROOT/projects/multica"
DESKTOP_DIR="$MULTICA_DIR/apps/desktop"
OVERLAY_DIR="$SCRIPT_DIR/overlay"
DIST_DIR="$SCRIPT_DIR/dist"

# --- Argument parsing ---
BUILD_ARM64=true
BUILD_X64=true
for arg in "$@"; do
  case "$arg" in
    --arm64-only) BUILD_X64=false ;;
    --x64-only)   BUILD_ARM64=false ;;
    --help|-h)
      echo "Usage: $0 [--arm64-only | --x64-only]"
      exit 0 ;;
  esac
done

# --- Sanity checks ---
if [ "$(uname)" != "Darwin" ]; then
  echo "Error: Mac DMG builds must run on macOS."
  exit 1
fi

if [ ! -d "$MULTICA_DIR" ]; then
  echo "Error: upstream not found at $MULTICA_DIR"
  echo ""
  echo "Clone it first:"
  echo "  git clone https://github.com/multica-ai/multica.git '$MULTICA_DIR'"
  exit 1
fi

if ! command -v pnpm &>/dev/null; then
  echo "Error: pnpm not found. Install via: npm install -g pnpm"
  exit 1
fi

# --- Checkout the target upstream version ---
echo "[build] Checking out upstream multica $MULTICA_VERSION..."
cd "$MULTICA_DIR"
git fetch --tags --quiet
git checkout "$MULTICA_VERSION" --quiet

# --- Apply overlay (saves original via git stash, restores on exit) ---
OVERLAY_TARGET="$MULTICA_DIR/apps/desktop/src/shared/runtime-config.ts"
OVERLAY_SOURCE="$OVERLAY_DIR/apps/desktop/src/shared/runtime-config.ts"
DESKTOP_PKG="$MULTICA_DIR/apps/desktop/package.json"

echo "[build] Stashing upstream changes in projects/multica..."
cd "$MULTICA_DIR"
# Stash the files we'll overlay so the git worktree is clean for version derivation
git stash push --quiet \
  -- apps/desktop/src/shared/runtime-config.ts \
     apps/desktop/package.json \
  2>/dev/null || true

# Ensure overlay is always restored on exit (success, error, or Ctrl-C)
cleanup() {
  echo ""
  echo "[build] Restoring upstream files..."
  cd "$MULTICA_DIR"
  git stash pop --quiet 2>/dev/null || true
}
trap cleanup EXIT

echo "[build] Applying RTMultica server overlay..."
cp "$OVERLAY_SOURCE" "$OVERLAY_TARGET"

# Add packageManager field so electron-builder detects pnpm (not npm).
# Without this, electron-builder falls back to npm's parent-dir module
# resolution, traverses the workspace-root node_modules symlinks into
# .pnpm, and fails with "unsafe path" on packages not in the desktop app's
# own dependency tree (e.g. @antfu/install-pkg added in v0.4.0).
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('$DESKTOP_PKG', 'utf8'));
pkg.packageManager = 'pnpm@10.28.2';
fs.writeFileSync('$DESKTOP_PKG', JSON.stringify(pkg, null, 2) + '\n');
"

# --- Install dependencies ---
echo "[build] Installing dependencies..."
cd "$MULTICA_DIR"
# Use --ignore-scripts to skip apps/web postinstall (fumadocs-mdx incompatible with Node v26)
# Then explicitly run desktop postinstall (electron-builder install-app-deps)
pnpm install --no-frozen-lockfile --ignore-scripts
cd "$DESKTOP_DIR"
pnpm exec electron-builder install-app-deps 2>/dev/null || true
cd "$MULTICA_DIR"

# --- Build ---
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/*.dmg "$DIST_DIR"/*.zip "$DIST_DIR"/*.blockmap
cd "$DESKTOP_DIR"

VERSION_CLEAN="${MULTICA_VERSION#v}"

if $BUILD_ARM64; then
  echo ""
  echo "[build] ── Building mac arm64 ──────────────────────────"
  CSC_IDENTITY_AUTO_DISCOVERY=false \
    node scripts/package.mjs --mac --arm64 --publish never
  # Collect only the current version DMG (version-scoped to avoid copying old cached files)
  find dist -maxdepth 1 -name "*${VERSION_CLEAN}*mac-arm64.dmg" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true
fi

if $BUILD_X64; then
  echo ""
  echo "[build] ── Building mac x64 ───────────────────────────"
  CSC_IDENTITY_AUTO_DISCOVERY=false \
    node scripts/package.mjs --mac --x64 --publish never
  # Collect only the current version DMG (version-scoped to avoid copying old cached files)
  find dist -maxdepth 1 -name "*${VERSION_CLEAN}*mac-x64.dmg" -exec cp {} "$DIST_DIR/" \; 2>/dev/null || true
fi

# --- Report ---
echo ""
echo "[build] ✓ Done. Output files:"
ls -lh "$DIST_DIR/"*.dmg 2>/dev/null || echo "  (no DMG files found — check build output above)"
