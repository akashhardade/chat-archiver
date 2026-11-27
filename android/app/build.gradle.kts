import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing. If key.properties (or the keystore it points to) is
// missing, release builds fall back to the debug signing config so the build
// never crashes.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val releaseStoreFile: File? =
    (keystoreProperties["storeFile"] as String?)?.let { rootProject.file(it) }?.takeIf { it.exists() }
val hasReleaseKeystore: Boolean =
    releaseStoreFile != null &&
        keystoreProperties["keyAlias"] != null &&
        keystoreProperties["keyPassword"] != null &&
        keystoreProperties["storePassword"] != null

// Web OAuth client ID for google_sign_in (Credential Manager). Keep in sync
// with Env.googleServerClientId / dart_defines.json.
val defaultWebClientId =
    "648674445211-hgsgbk6vm0hpoe16gtoii3jb9pebaj2h.apps.googleusercontent.com"

android {
    namespace = "com.vervali.chatarchiver"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.vervali.chatarchiver"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Used by google_sign_in_android when Dart does not pass serverClientId.
        resValue("string", "default_web_client_id", defaultWebClientId)
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Enable ProGuard with default rules only
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    testOptions {
        unitTests {
            // android.util.Log etc. return defaults instead of throwing in JVM tests.
            isReturnDefaultValues = true
        }
    }

    flavorDimensions += "default"

    productFlavors {
        create("dev") {
            dimension = "default"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Chat Archiver Dev")
            // Label of our share target. The runner reads this string at runtime.
            resValue("string", "share_label", "Save to Chat Archiver Dev")
        }

        create("prod") {
            dimension = "default"
            resValue("string", "app_name", "Chat Archiver")
            resValue("string", "share_label", "Save to Chat Archiver")
        }

        create("stage") {
            dimension = "default"
            applicationIdSuffix = ".stage"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Chat Archiver Staging")
            resValue("string", "share_label", "Save to Chat Archiver Staging")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
    // Real org.json for JVM tests (android.jar only has stubs).
    testImplementation("org.json:json:20240303")
}
