plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.merkaerp.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.merkaerp.app"
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
            // Signing with the debug keys for now, so lutter run --release works.
            val storePath = providers.gradleProperty("MERKA_RELEASE_STORE_FILE").orNull
                ?: System.getenv("MERKA_RELEASE_STORE_FILE")
            val alias = providers.gradleProperty("MERKA_RELEASE_KEY_ALIAS").orNull
                ?: System.getenv("MERKA_RELEASE_KEY_ALIAS")
            val storePass = providers.gradleProperty("MERKA_RELEASE_STORE_PASSWORD").orNull
                ?: System.getenv("MERKA_RELEASE_STORE_PASSWORD")
            val keyPass = providers.gradleProperty("MERKA_RELEASE_KEY_PASSWORD").orNull
                ?: System.getenv("MERKA_RELEASE_KEY_PASSWORD")
            if (!storePath.isNullOrBlank() && !alias.isNullOrBlank() &&
                !storePass.isNullOrBlank() && !keyPass.isNullOrBlank()) {
                signingConfig = signingConfigs.create("productionRelease") {
                    storeFile = file(storePath)
                    keyAlias = alias
                    storePassword = storePass
                    keyPassword = keyPass
                }
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any {
        it.name.contains("Release", ignoreCase = true) &&
            (it.name.contains("assemble", ignoreCase = true) ||
                it.name.contains("bundle", ignoreCase = true) ||
                it.name.contains("package", ignoreCase = true))
    }
    val required = listOf(
        "MERKA_RELEASE_STORE_FILE",
        "MERKA_RELEASE_KEY_ALIAS",
        "MERKA_RELEASE_STORE_PASSWORD",
        "MERKA_RELEASE_KEY_PASSWORD",
    )
    val missing = required.filter {
        providers.gradleProperty(it).orNull.isNullOrBlank() &&
            System.getenv(it).isNullOrBlank()
    }
    if (releaseRequested && missing.isNotEmpty()) {
        throw GradleException(
            "Release bloqueado: faltan credenciales de firma: ${missing.joinToString()}"
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
