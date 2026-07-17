# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

RTMultica **repackages** the upstream [Multica](https://github.com/multica-ai/multica) app into
distributable clients that point at a **self-hosted server** instead of upstream's cloud:

- **Android** — a Capacitor WebView shell that loads the remote server directly.
- **macOS Desktop** — the upstream Electron app, rebuilt with an overlay that rewrites its server URLs.
- **Server** — docker-compose + systemd files for self-hosting the Multica backend.

**This repo contains almost no application source code.** The UI/app code lives upstream. Two
directories that look important are gitignored and never committed here:

- `www/` — Capacitor `webDir` (a Capacitor artifact; the app actually loads the remote URL, so this is effectively empty).
- `projects/multica/` — a read-only clone of upstream, required only for desktop builds.

When a change is requested, first decide *which target* (Android shell, desktop overlay, or server
deploy) — the app's actual behavior is usually not editable from this repo.

## Android client (Capacitor)

- `capacitor.config.json` sets `server.url` = `https://mtc.naivehero.top:8443`. The APK is a thin
  WebView that loads that URL; there is no local web bundle. `npm run build` is intentionally a no-op.
- `android/app/build.gradle` builds **ABI splits** (`arm64-v8a`, `armeabi-v7a`, `x86_64`) plus a
  `universalApk`. Signing is only applied when `KEYSTORE_PATH` env is set (CI); local builds are unsigned.
- Build/release is automated: `.github/workflows/build-android.yml` runs on push to `main` touching
  `android/**`, `www/**`, `package.json`, `capacitor.config.json`, or the workflow itself. It signs
  with `SIGNING_KEY_BASE64` / `KEY_*` secrets and publishes all APKs to the `android-latest` GitHub Release.

Local Android commands:

```bash
npm ci
npx cap sync android              # sync config/plugins into android/
cd android && ./gradlew assembleRelease   # needs KEYSTORE_* env to sign, else unsigned
```

## Desktop client (`desktop/build.sh`)

Run **on macOS** (`Go`, `Node 22`, `pnpm` required, plus `projects/multica` cloned):

```bash
cd desktop && ./build.sh              # both arm64 + x64 DMGs
cd desktop && ./build.sh --arm64-only
cd desktop && ./build.sh --x64-only
```

How it works — read `desktop/build.sh` before changing it:

1. `git checkout` the pinned upstream tag (`MULTICA_VERSION` at the top of the script).
2. **Overlay**: copies `desktop/overlay/apps/desktop/src/shared/runtime-config.ts` over upstream's
   copy. The overlay changes `DEFAULT_RUNTIME_CONFIG` to point at `mtcsrv.naivehero.top:8443`
   (this is the single source of truth for the desktop app's server address).
3. Injects `packageManager: pnpm@...` into upstream's `apps/desktop/package.json` so electron-builder
   detects pnpm (without it, electron-builder falls into npm resolution and fails with "unsafe path").
4. Installs with `--ignore-scripts` (upstream's web postinstall breaks on new Node), then runs
   electron-builder's `install-app-deps` explicitly.
5. Builds unsigned DMGs (`CSC_IDENTITY_AUTO_DISCOVERY=false`) into `desktop/dist/`.

Upstream files are edited in place but **restored via `git stash` on exit** (a `trap cleanup EXIT`),
so the upstream clone stays clean.

## Server deploy (`deploy/`)

- `docker-compose.mutica.yml` — self-hosts the Multica backend: `tensorzero/postgres:17` (with
  pg_cron) + `ghcr.io/multica-ai/multica-backend`. Config comes from env vars (JWT, CORS, upload
  paths, Resend/SMTP for email verification). Backend listens on `8080`.
- `setup-multica-daemon.sh` — installs the `multica` CLI as a **systemd user service** with linger
  enabled; run as a normal user, not root.

## Releasing (version bump discipline)

Git history is almost entirely `chore: bump version to X`. A release touches **three independent
version fields that must be kept in sync**:

- `android/app/build.gradle` → `versionName` **and** `versionCode`.
  ⚠️ `versionCode` **must strictly increase** every release — a stale/lower code causes Android
  "downgrade install" failures (see commit 55507c4).
- `desktop/build.sh` → `MULTICA_VERSION` (the upstream tag desktop builds against).
- `capacitor.config.json` server URLs and the overlay `runtime-config.ts` are the two places server
  addresses live; note Android and desktop point at **different hosts** (`mtc.` vs `mtcsrv.`).
