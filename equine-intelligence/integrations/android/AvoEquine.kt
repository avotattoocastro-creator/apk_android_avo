package org.avoperformance.horse.engine

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant

/**
 * Kotlin access to the AVO Equine Intelligence Engine (C++ libavo_equine.so, same code as Windows).
 * Heavy work always runs on Dispatchers.Default, never on the UI thread. Returns the analysis JSON
 * (format "avo-equine-analysis" v1, see equine-intelligence/docs/FORMATO_RESULTADOS.md).
 */
object AvoEquine {
    private val loaded: Boolean = runCatching { System.loadLibrary("avo_equine_jni"); true }.getOrDefault(false)
    val available: Boolean get() = loaded

    @JvmStatic private external fun nativeAnalyse(paths: Array<String>, processedAt: String?, series: Boolean): String
    @JvmStatic private external fun nativeVersion(): String

    fun version(): String? = if (loaded) nativeVersion() else null

    suspend fun analyse(segments: List<File>, withSeries: Boolean = false): String = withContext(Dispatchers.Default) {
        check(loaded) { "motor de análisis no incluido en esta compilación" }
        nativeAnalyse(segments.map { it.absolutePath }.toTypedArray(), Instant.now().toString(), withSeries)
    }
}
