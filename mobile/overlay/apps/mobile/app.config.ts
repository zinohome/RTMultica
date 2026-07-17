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
    // Portrait-locked: the UI is designed for phone portrait (upstream
    // ios.supportsTablet = false). On the Xiaomi Pad 5 Pro it runs portrait,
    // which is stable — rotating a phone-first layout risks broken screens.
    orientation: "portrait",
    userInterfaceStyle: "automatic",
    scheme: "multica",
    icon: "./assets/icon.png",
    ios: {
      supportsTablet: false,
      bundleIdentifier: isProd
        ? (process.env.EXPO_BUNDLE_IDENTIFIER_PROD ?? "ai.multica.mobile")
        : isStaging
          ? "ai.multica.mobile.staging"
          : (process.env.EXPO_BUNDLE_IDENTIFIER_DEV ?? "ai.multica.mobile.dev"),
    },
    // RTMultica addition — Android target (upstream has none).
    android: {
      package: "top.naivehero.multica.rn",
      versionCode: 1,
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
