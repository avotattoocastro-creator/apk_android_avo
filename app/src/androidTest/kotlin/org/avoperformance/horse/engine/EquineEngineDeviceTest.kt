package org.avoperformance.horse.engine

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.avoperformance.horse.core.engine.EquineResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * On a device or emulator: RAW (SYNTHETIC test session in androidTest assets) -> JNI -> C++ engine -> JSON ->
 * Kotlin model used by the screens. Verifies the packaged .so, UTF-8 paths, persistence and cancellation.
 * It does NOT validate accuracy on real horses.
 */
@RunWith(AndroidJUnit4::class)
class EquineEngineDeviceTest {
    private fun session(): File {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val test = InstrumentationRegistry.getInstrumentation().context
        val dir = File(ctx.cacheDir, "equine_test").apply { deleteRecursively(); mkdirs() }
        val f = File(dir, "sesión_🐎.avr")
        test.assets.open("synthetic_session.avo").use { i -> f.outputStream().use { i.copyTo(it) } }
        return f
    }

    @Test fun nativeLibraryLoadsAndAnalysesASessionEndToEnd() {
        assertTrue(AvoEquine.unavailableReason ?: "", AvoEquine.available)
        assertTrue(AvoEquine.version()!!.startsWith("1.1.0"))
        val f = session()
        val cache = File(f.parentFile, "analisis")
        val opts = "{\"series\":true,\"cache_dir\":\"${cache.absolutePath}\"}"
        val before = f.readBytes()
        val text = AvoEquine.text(AvoEquine.nativeAnalyse(arrayOf(AvoEquine.utf8(f.absolutePath)), AvoEquine.utf8(opts), 0))
        val r = EquineResult.parse(text)
        assertEquals("SINTETICA_0001", r.sessionId)
        assertEquals("CALCULADO", r.cache)
        assertTrue(r.hasImu)
        assertEquals(0.95, r.performance.segments.first { it.code == "WALK" }.cadenceHz!!, 0.03)
        assertEquals(1, r.curves.size)
        assertTrue(r.series!!.t.isNotEmpty() && r.girth!!.t.isNotEmpty())
        val again = EquineResult.parse(AvoEquine.text(AvoEquine.nativeAnalyse(arrayOf(AvoEquine.utf8(f.absolutePath)), AvoEquine.utf8(opts), 0)))
        assertEquals("ACIERTO", again.cache)
        assertTrue(before.contentEquals(f.readBytes()))     // RAW untouched
    }

    @Test fun cancellationIsHonoured() {
        val f = session()
        val token = AvoEquine.nativeNewToken()
        try {
            AvoEquine.nativeCancel(token)
            val text = AvoEquine.text(AvoEquine.nativeAnalyse(arrayOf(AvoEquine.utf8(f.absolutePath)), AvoEquine.utf8("{}"), token))
            assertTrue(text, text.contains("\"cancelado\":true"))
        } finally { AvoEquine.nativeFreeToken(token) }
    }
}
