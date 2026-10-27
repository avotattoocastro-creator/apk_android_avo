// AVO Tarjetas: creates the personal NFC cards (AvoUserCard) for the AVO Performance Horse app.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "org.avoperformance.cards"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.avoperformance.cards"
        minSdk = 29
        targetSdk = 35
        versionCode = 3
        versionName = "1.2-roles-dev1"
    }

    signingConfigs {
        // Same stable key as the main app, ONLY from environment variables (CI secrets).
        create("release") {
            val ks = System.getenv("AVO_KEYSTORE_FILE")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("AVO_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("AVO_KEY_ALIAS")
                keyPassword = System.getenv("AVO_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        debug { if (System.getenv("AVO_KEYSTORE_FILE") != null) signingConfig = signingConfigs.getByName("release") }
        release {
            isMinifyEnabled = false
            if (System.getenv("AVO_KEYSTORE_FILE") != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    // Same visual style as the main app: the AVO theme and components are compiled from their single source
    // (app/.../ui/theme and ui/components), so any style change applies to both apps.
    sourceSets["main"].java.srcDirs(
        "../app/src/main/kotlin/org/avoperformance/horse/ui/theme",
        "../app/src/main/kotlin/org/avoperformance/horse/ui/components",
        // SecureStore (Android Keystore AES-GCM): protects the licence signing key at rest
        "../app/src/main/kotlin/org/avoperformance/horse/security",
    )
    lint { abortOnError = false; checkReleaseBuilds = false }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.coroutines.android)
}
