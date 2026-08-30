plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.messenger.mobile_messenger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (used to show a
        // notification while the app is in the foreground — see
        // lib/services/push_notification_service.dart), which relies on
        // Java 8+ APIs the Android runtime itself doesn't provide below
        // API 26 without this desugaring step.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.messenger.mobile_messenger"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Applied conditionally, not in the `plugins {}` block above, because
// the google-services Gradle plugin fails the entire build immediately
// if google-services.json is missing — and this repository doesn't ship
// one (it's a real Firebase project's credentials; see
// docs/PUSH_NOTIFICATIONS.md for how to generate your own). Until that
// file exists here, the app builds and runs exactly as before, just
// without push notifications; dropping in a real google-services.json
// activates this plugin on the next build with no other change needed.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
