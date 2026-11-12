plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.attendance.ble.attendance_ble_test"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.attendance.ble.attendance_ble_test"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += listOf("variant")
    productFlavors {
        create("prod") {
            dimension = "variant"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}



flutter {
    source = "../.."
}

// Strict Google Services enforcement:
// Non-spike / production branch requires valid Firebase configuration.
// If google-services.json is missing, fail loudly with a fatal GradleException.
if (!file("google-services.json").exists()) {
    throw GradleException(
        "\n=======================================================================\n" +
        "FATAL: android/app/google-services.json is missing!\n" +
        "Production builds require a valid Firebase configuration file.\n" +
        "Please copy your google-services.json into android/app/ before building.\n" +
        "=======================================================================\n"
    )
}
apply(plugin = "com.google.gms.google-services")
