// Pure Kotlin/JVM module: protocol, NTRIP, RTCM, RAW parser, sync rules.
// No Android dependency, so every piece is unit-tested on the JVM.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

java { toolchain { languageVersion.set(JavaLanguageVersion.of(17)) } }
kotlin { jvmToolchain(17) }

dependencies {
    api(libs.coroutines.core)
    testImplementation(libs.junit)
}

tasks.test {
    testLogging { events("passed", "failed", "skipped"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
