plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

android {
    namespace = "org.avoperformance.horse"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.avoperformance.horse"
        minSdk = 29          // Android 10
        targetSdk = 35
        versionCode = 31
        versionName = "2.3-wifi-dev6"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // AVO Equine Intelligence Engine (C++17, equine-intelligence/) built with the NDK for the supported ABIs
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
        externalNativeBuild { cmake { arguments += listOf("-DANDROID_STL=c++_static") } }
    }

    ndkVersion = "27.0.12077973"
    externalNativeBuild {
        cmake {
            path = file("../equine-intelligence/integrations/android/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        // Release signing ONLY from environment variables (CI secrets). Nothing in source control.
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
        // Stable signing: when CI has the AVO_KEYSTORE_* secrets, the debug APK is signed with the
        // same key, so each new version installs over the previous one without losing data.
        debug {
            if (System.getenv("AVO_KEYSTORE_FILE") != null) signingConfig = signingConfigs.getByName("release")
        }
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
    buildFeatures { compose = true; buildConfig = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    lint { abortOnError = false; checkReleaseBuilds = false }
}

ksp { arg("room.schemaLocation", "$projectDir/schemas") }

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.navigation.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.core)
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.work.runtime.ktx)
    implementation(libs.coroutines.android)
    implementation(libs.osmdroid)
    // App-to-app sending over the internet (Firebase Spark: Authentication + Realtime Database)
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-database")
    testImplementation(libs.junit)
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}
