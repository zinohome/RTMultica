#!/usr/bin/env node
// Post-prebuild patch for the generated Android project.
//
// `expo prebuild --platform android` emits an app/build.gradle whose release
// buildType signs with the DEBUG keystore. This script:
//   1. adds a `release` signingConfig that reads the keystore from env
//      (KEYSTORE_PATH / KEY_STORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD — the
//      same secrets the existing Capacitor workflow uses),
//   2. points the release buildType at it when a keystore is present
//      (falls back to debug signing for unsigned local builds),
//   3. pins reactNativeArchitectures to arm64-v8a — both target devices
//      (Xiaomi 14 Pro, Xiaomi Pad 5 Pro) are arm64, and dropping the other
//      ABIs roughly halves APK size and speeds up the New-Architecture build.
//
// Idempotent: re-running on an already-patched project is a no-op.
//
// Usage: node inject-android-signing.mjs <path-to-android-dir>

import fs from "node:fs";
import path from "node:path";

const androidDir = process.argv[2];
if (!androidDir) {
  console.error("[sign] ERROR: pass the android/ directory path as arg 1");
  process.exit(1);
}

const buildGradle = path.join(androidDir, "app", "build.gradle");
const gradleProps = path.join(androidDir, "gradle.properties");

// ---- 1. app/build.gradle : release signingConfig ----
let g = fs.readFileSync(buildGradle, "utf8");

if (g.includes("RTMULTICA_RELEASE_SIGNING")) {
  console.log("[sign] build.gradle already patched — skipping");
} else {
  const injected = `signingConfigs {
        // RTMULTICA_RELEASE_SIGNING — keystore from env (CI secrets or local).
        // Leaving env unset yields an unsigned/debug-signed build.
        release {
            def ksPath = System.getenv("KEYSTORE_PATH")
            if (ksPath != null) {
                storeFile file(ksPath)
                storePassword System.getenv("KEY_STORE_PASSWORD")
                keyAlias System.getenv("KEY_ALIAS")
                keyPassword System.getenv("KEY_PASSWORD")
            }
        }`;

  const before = g;
  g = g.replace(/signingConfigs\s*\{/, injected);
  if (g === before) {
    console.error("[sign] ERROR: could not find `signingConfigs {` in build.gradle");
    process.exit(1);
  }

  // Point the RELEASE buildType at signingConfigs.release. In the RN template
  // the debug buildType's `signingConfig signingConfigs.debug` appears first
  // and the release buildType's appears last, so replace the LAST occurrence.
  const marker = "signingConfig signingConfigs.debug";
  const lastIdx = g.lastIndexOf(marker);
  if (lastIdx === -1) {
    console.error("[sign] ERROR: could not find release `signingConfig signingConfigs.debug`");
    process.exit(1);
  }
  const replacement =
    'signingConfig (System.getenv("KEYSTORE_PATH") != null ? signingConfigs.release : signingConfigs.debug)';
  g = g.slice(0, lastIdx) + replacement + g.slice(lastIdx + marker.length);

  fs.writeFileSync(buildGradle, g);
  console.log("[sign] injected release signingConfig into app/build.gradle");
}

// ---- 2. gradle.properties : ABI pin ----
let p = fs.readFileSync(gradleProps, "utf8");
const abiLine = "reactNativeArchitectures=arm64-v8a";
if (/^reactNativeArchitectures=.*$/m.test(p)) {
  const updated = p.replace(/^reactNativeArchitectures=.*$/m, abiLine);
  if (updated !== p) {
    p = updated;
    fs.writeFileSync(gradleProps, p);
    console.log("[sign] pinned reactNativeArchitectures=arm64-v8a");
  } else {
    console.log("[sign] reactNativeArchitectures already arm64-v8a");
  }
} else {
  p += `\n${abiLine}\n`;
  fs.writeFileSync(gradleProps, p);
  console.log("[sign] added reactNativeArchitectures=arm64-v8a");
}

console.log("[sign] done");
