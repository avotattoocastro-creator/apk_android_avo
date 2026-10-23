plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "org.avoperformance.horse.update"
    compileSdk = 35
    defaultConfig { applicationId = "org.avoperformance.horse.update"; minSdk = 29; targetSdk = 35; versionCode = 20; versionName = "2.0.0" }
    signingConfigs { create("production") {
        val path = System.getenv("AVO_UPDATER_KEYSTORE_FILE")
        if (!path.isNullOrBlank()) { storeFile = file(path); storePassword = System.getenv("AVO_UPDATER_KEYSTORE_PASSWORD"); keyAlias = System.getenv("AVO_UPDATER_KEY_ALIAS"); keyPassword = System.getenv("AVO_UPDATER_KEY_PASSWORD") }
    } }
    buildTypes { getByName("release") { isMinifyEnabled = false; if (!System.getenv("AVO_UPDATER_KEYSTORE_FILE").isNullOrBlank()) signingConfig = signingConfigs.getByName("production") } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

dependencies { testImplementation("junit:junit:4.13.2") }
