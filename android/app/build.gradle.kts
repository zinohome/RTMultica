plugins {
    id("com.android.application")
}

android {
    namespace = "top.naivehero.multica"
    compileSdk = 34

    defaultConfig {
        applicationId = "top.naivehero.multica"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        create("release") {
            val ksPath = System.getenv("KEYSTORE_PATH")
            if (!ksPath.isNullOrEmpty()) {
                storeFile = file(ksPath)
                storePassword = System.getenv("KEY_STORE_PASSWORD") ?: ""
                keyAlias = System.getenv("KEY_ALIAS") ?: "multica"
                keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            val ksPath = System.getenv("KEYSTORE_PATH")
            if (!ksPath.isNullOrEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // 输出 arm64-v8a 专用包 + universal 包，兼容 Xiaomi Pad 5 Pro 等平板设备
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("com.google.androidbrowserhelper:androidbrowserhelper:2.5.0")
}
