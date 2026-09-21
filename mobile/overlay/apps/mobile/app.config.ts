import type { ExpoConfig, ConfigContext } from "expo/config";

/**
 * RTMultica overlay of upstream apps/mobile/app.config.ts.
 *
 * Upstream ships iOS-only config (no `android:` block, no android scripts).
 * This overlay ADDS the Android target so the RN app can build an APK, while
 * leaving the iOS config untouched. Applied over upstream by
 * mobile/build-android.sh and the build-android-native.yml CI workflow.
 *
 * When bumping MULTICA_VERSION, re-sync this file against upstream's
 * app.config.ts (diff the iOS/plugins sections) — only the `android:` block,
 * the prod `name`, and this header are RTMultica additions.
 */
export default ({ config }: ConfigContext): ExpoConfig => {
  const env = process.env.APP_ENV ?? "development";
  const isProd = env === "production";
  const isStaging = env === "staging";

  return {
    ...config,
    // RTMultica: prod display name distinguishes the native RN build from the
    // existing Capacitor shell ("Multica") so both can coexist on one device.
    name: isProd
      ? "Multica RN"
      : isStaging
        ? "Multica RN (Staging)"
        : "Multica RN (Dev)",
    slug: "multica-mobile",
    version: "0.1.0",
    // Portrait-locked: the UI is designed for phone portrait. Upstream now
    // sets ios.supportsTablet = true (iPad multitasking support), but on the
    // Xiaomi Pad 5 Pro this app only ever runs portrait, which is stable —
    // rotating a phone-first layout risks broken screens.
    orientation: "portrait",
    userInterfaceStyle: "automatic",
    scheme: "multica",
    icon: "./assets/icon.png",
    ios: {
      // Expo keeps the top-level portrait policy for iPhone while adding all
      // iPad orientations required for multitasking when tablet support is on.
      supportsTablet: true,
      // Pins DEVELOPMENT_TEAM on every prebuild. Leaving it unset is the normal
      // path — `expo run:ios` then resolves a signing identity from the Keychain
      // itself, which is right when the Apple ID owns exactly one team. With
      // several (a personal team plus an employer's) it takes the *first*
      // identity found whenever the terminal is non-interactive, writes that
      // choice into the generated ios/, and never clears it again: prebuild only
      // writes DEVELOPMENT_TEAM when a value is present, so a project pinned to
      // the wrong team stays wrong until ios/ is deleted. Setting this re-applies
      // the intended team on every `scripts/ios-run.sh` run, which also repairs
      // an already-mispinned checkout.
      appleTeamId: process.env.EXPO_APPLE_TEAM_ID,
      bundleIdentifier: isProd
        ? (process.env.EXPO_BUNDLE_IDENTIFIER_PROD ?? "ai.multica.mobile")
        : isStaging
          ? "ai.multica.mobile.staging"
          : (process.env.EXPO_BUNDLE_IDENTIFIER_DEV ?? "ai.multica.mobile.dev"),
    },
    // RTMultica addition — Android target (upstream has none).
    android: {
      package: "top.naivehero.multica.rn",
      versionCode: 2,
      // Android 15+ enforces edge-to-edge; opting in explicitly keeps the
      // status/nav bars laid out correctly across Xiaomi's HyperOS skin.
      edgeToEdgeEnabled: true,
      adaptiveIcon: {
        foregroundImage: "./assets/icon.png",
        backgroundColor: "#ffffff",
      },
      // Mirrors the iOS photo-library permission (expo-image-picker); camera
      // and microphone stay disabled as upstream does.
      permissions: ["READ_MEDIA_IMAGES"],
    },
    plugins: [
      "expo-router",
      "expo-secure-store",
      "@react-native-community/datetimepicker",
      "react-native-enriched-markdown",
      [
        "expo-image-picker",
        {
          photosPermission:
            "Allow Multica to access your photos to attach images to issues and comments.",
          cameraPermission: false,
          microphonePermission: false,
        },
      ],
      [
        "expo-build-properties",
        {
          ios: {
            buildReactNativeFromSource: true,
          },
        },
      ],
    ],
    extra: { APP_ENV: env },
  };
};
