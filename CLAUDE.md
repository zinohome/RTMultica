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

## Android client — native (React Native, `mobile/`)

A **second, true-native** Android client built from upstream's Expo/React Native
app (`apps/mobile`), running in parallel with the Capacitor shell above (different
package, both installable at once). This is the real-native path — RN renders
native components, not a WebView.

- Upstream `apps/mobile` ships **iOS-only** config (no `android:` block, no android
  scripts). RTMultica adds Android support via an overlay, exactly like the desktop
  overlay pattern — see `docs/superpowers/specs/2026-07-17-rtmultica-android-native-rn-design.md`.
- `mobile/overlay/apps/mobile/` — files copied over upstream at build time:
  - `.env.production` → `EXPO_PUBLIC_API_URL=https://mtcsrv.naivehero.top:8443` (API host,
    same as desktop's `apiUrl`; ws is derived in-app) + `EXPO_PUBLIC_WEB_URL=https://mtc.naivehero.top:8443`.
    ⚠️ This file is force-tracked past `.gitignore`'s `*.env.production` rule (holds only public URLs).
  - `app.config.ts` → adds the `android:` block: package `top.naivehero.multica.rn`,
    display name `Multica RN`, adaptive icon, edge-to-edge, `READ_MEDIA_IMAGES`.
    **Full-file overlay** — re-sync against upstream when bumping `MULTICA_VERSION`.
- `mobile/scripts/inject-android-signing.mjs` — post-prebuild patch: injects a release
  `signingConfig` reading the keystore from env (reuses the Capacitor secrets:
  `KEYSTORE_PATH`/`KEY_STORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`), and pins
  `reactNativeArchitectures=arm64-v8a` (both target devices are arm64; halves APK size).
- `mobile/build-android.sh` — local build, mirrors `desktop/build.sh` (checkout tag →
  overlay via git stash → `expo prebuild` → inject signing → `gradlew assembleRelease`).
  **`EXPO_PUBLIC_*` must be exported into the environment** (the script `source`s the
  overlay `.env`) — Metro inlines env vars into the release bundle; the `.env` file alone
  isn't auto-loaded when invoking expo directly.
- CI: `.github/workflows/build-android-native.yml` — ubuntu runner clones upstream at the
  pinned tag, applies overlay, prebuilds, signs, `gradlew assembleRelease`, publishes to
  the **`android-native-latest`** GitHub Release (distinct from the shell's `android-latest`).
  Triggers on push to `main`/`android-native-build` touching `mobile/**` or the workflow.

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
- `mobile/build-android.sh` **and** `.github/workflows/build-android-native.yml` →
  `MULTICA_VERSION` (upstream tag the RN Android app builds against; keep both in sync).
  The RN app's own `versionCode`/`versionName` live in `mobile/overlay/apps/mobile/app.config.ts`
  under `android.versionCode` — an **independent** series from the Capacitor `build.gradle` one
  (different package), so it starts at 1 and increments on its own.
- `capacitor.config.json` server URLs and the overlay `runtime-config.ts` are the two places server
  addresses live; note Android and desktop point at **different hosts** (`mtc.` vs `mtcsrv.`).
