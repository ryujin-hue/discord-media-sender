import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials are read from `android/key.properties` when the
// file exists, otherwise from the environment variables that GitHub Actions
// provides. The keystore itself is never committed.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystoreFile = keystorePropertiesFile.exists()
if (hasKeystoreFile) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun secret(name: String): String? =
    (keystoreProperties.getProperty(name) ?: System.getenv(name))?.takeIf { it.isNotBlank() }

android {
    namespace = "com.dmsender.discord_media_sender"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dmsender.discord_media_sender"
        // Android 7.0 (API 24) is the minimum supported version, unchanged
        // from the 1.0 build so that upgrades keep working.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("en")
    }

    signingConfigs {
        create("release") {
            val storePath = secret("DMS_KEYSTORE_PATH")
                ?: (if (hasKeystoreFile) keystoreProperties.getProperty("storeFile") else null)
            if (storePath != null) {
                // `storeFile` is resolved against the root project so that
                // `keystore/dms-release.jks` refers to `android/keystore/…`.
                storeFile = rootProject.file(storePath)
                storePassword = secret("DMS_KEYSTORE_PASSWORD")
                    ?: keystoreProperties.getProperty("storePassword")
                keyAlias = secret("DMS_KEY_ALIAS")
                    ?: keystoreProperties.getProperty("keyAlias")
                keyPassword = secret("DMS_KEY_PASSWORD")
                    ?: keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null &&
                releaseSigning.storeFile != null &&
                releaseSigning.storeFile!!.exists() &&
                releaseSigning.keyPassword != null
            ) {
                signingConfig = releaseSigning
            } else {
                // A release build without configured signing credentials still
                // produces an installable (unsigned) APK so that CI can verify
                // the build; the release workflow always provides the secrets.
                signingConfig = signingConfigs.getByName("debug")
                logger.warn(
                    "No release signing credentials found; the APK is signed with " +
                        "the debug key. Configure android/key.properties or the " +
                        "DMS_KEYSTORE_* environment variables."
                )
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isMinifyEnabled = false
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1", "META-INF/*.kotlin_module")
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
