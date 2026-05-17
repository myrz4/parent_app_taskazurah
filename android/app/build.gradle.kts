import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin") // must come last
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val isBundleBuild = gradle.startParameter.taskNames.any {
    it.contains("bundle", ignoreCase = true)
}
val keepApkDebugSymbols = providers.gradleProperty("taskaKeepApkDebugSymbols")
    .map { it.equals("true", ignoreCase = true) }
    .orElse(false)
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { stream ->
        keystoreProperties.load(stream)
    }
} else if (isReleaseBuild) {
    logger.warn(
        "Android release build is using debug signing because android/key.properties is missing. " +
            "Add android/key.properties before publishing to Play Store or distributing a production Android release.",
    )
}

android {
    namespace = "com.example.parent_app"
    compileSdk = 36 // ✅ updated for new plugins

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    packaging {
        jniLibs {
            // Keep symbol-heavy native libraries out of release APKs by default.
            // If Windows strip failures return, opt back in with:
            //   .\gradlew assembleRelease -PtaskaKeepApkDebugSymbols=true
            if (!isBundleBuild && keepApkDebugSymbols.get()) {
                keepDebugSymbols += setOf("**/*.so")
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.parent_app"
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }

            // Use a real release keystore when android/key.properties exists.
            // Fall back to debug signing so local validation builds still work.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    ndkVersion = flutter.ndkVersion
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ upgraded desugar_jdk_libs to match flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7")
}
