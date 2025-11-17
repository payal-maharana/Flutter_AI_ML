plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin must be applied after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // 👇 Add this Firebase plugin
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.test_ml"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.test_ml"

        // 👇 ML Kit requires at least 21
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Enable MultiDex (optional if minSdk < 21)
        multiDexEnabled = true
    }

    buildTypes {
        getByName("release") {
            // Temporary signing config for testing
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.22")
    // 👇 Only if you get "64K methods" error (safe to keep)
    implementation("androidx.multidex:multidex:2.0.1")

    // (Optional) You don't need to manually add ML Kit libs because
    // the google_ml_kit Flutter plugin pulls them automatically.
    // But if Gradle complains about missing dependency, you can add:
    // implementation("com.google.mlkit:text-recognition:16.0.0")

    // If you plan to use other Firebase libs (auth, analytics, etc.)
    // implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
}
