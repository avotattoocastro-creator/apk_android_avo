package org.avoperformance.horse.engine

/**
 * JNI access to the AVO Equine Intelligence Engine (libavo_equine_jni.so, the same C++ code as Windows and Python).
 * Strings travel as UTF-8 byte arrays. Every call is blocking: callers run it on Dispatchers.Default.
 * The native bridge is equine-intelligence/integrations/android/jni/avo_eq_jni.cpp.
 */
object AvoEquine {
    private val loadError: Throwable? = runCatching { System.loadLibrary("avo_equine_jni") }.exceptionOrNull()
    val available: Boolean get() = loadError == null
    val unavailableReason: String? get() = loadError?.let { "motor de análisis no disponible en este dispositivo: ${it.message}" }

    @JvmStatic external fun nativeNewToken(): Long
    @JvmStatic external fun nativeCancel(token: Long)
    @JvmStatic external fun nativeFreeToken(token: Long)
    @JvmStatic external fun nativeAnalyse(paths: Array<ByteArray>, options: ByteArray, token: Long): ByteArray
    @JvmStatic external fun nativeCompare(a: Array<ByteArray>, b: Array<ByteArray>, options: ByteArray, token: Long): ByteArray
    @JvmStatic external fun nativeCacheInvalidate(dir: ByteArray): Int
    @JvmStatic external fun nativeVersion(): ByteArray
    @JvmStatic external fun nativeApiVersion(): Int

    fun version(): String? = if (available) String(nativeVersion(), Charsets.UTF_8) else null

    internal fun utf8(s: String) = s.toByteArray(Charsets.UTF_8)
    internal fun text(b: ByteArray) = String(b, Charsets.UTF_8)
}
