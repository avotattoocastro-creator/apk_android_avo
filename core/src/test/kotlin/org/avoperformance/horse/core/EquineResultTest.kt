package org.avoperformance.horse.core

import org.avoperformance.horse.core.engine.EqComparison
import org.avoperformance.horse.core.engine.EquineResult
import org.avoperformance.horse.core.engine.MiniJson
import org.avoperformance.horse.core.raw.TrainingAnalyzer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

/**
 * RAW -> C++ engine -> JSON -> Kotlin model. The JSON fixtures are produced by the engine (avo_eq_cli) from the
 * RAW files next to them; the CI regenerates them and fails if they drift (build-equine-engine.yml).
 * synthetic_session.avo is SYNTHETIC: these checks verify the chain, not accuracy on real horses.
 */
class EquineResultTest {
    private fun text(name: String) = String(TestRes.bytes(name), Charsets.UTF_8)

    @Test fun syntheticSessionWithGirthGoesThroughTheWholeChain() {
        val r = EquineResult.parse(text("equine/synthetic_analysis.json"))
        assertEquals(2, r.formatVersion)
        assertTrue(r.engine.startsWith("1.1.0"))
        assertEquals("SINTETICA_0001", r.sessionId)
        assertTrue(r.hasImu && r.hasGnss)
        assertEquals("OFFLINE_ANALYSIS", r.mode)
        assertEquals(16, r.inputFingerprint.length)
        assertTrue(r.algorithms.containsKey("GAIT_CLASSIFIER_V1") && r.algorithms.containsKey("GAIT_CLASSIFIER_V2"))
        // per-gait performance: walk then trot with the synthetic cadences (0.95 / 1.45 Hz)
        val walk = r.performance.segments.first { it.code == "WALK" }
        val trot = r.performance.segments.first { it.code == "TROT" }
        assertEquals(0.95, walk.cadenceHz!!, 0.02)
        assertEquals(1.45, trot.cadenceHz!!, 0.02)
        assertEquals(1.5 / 0.95, walk.strideLengthM!!, 0.05)
        assertEquals(1, r.curves.size)
        assertEquals("DERECHA", r.curves[0].direction)
        assertEquals(20.0, r.curves[0].radiusM, 1.5)
        assertTrue(r.events.any { it.type == "TRANSICION_AIRE" })
        assertTrue(r.events.all { it.id.startsWith("EV") && it.version.isNotEmpty() && it.reason.isNotEmpty() })
        assertEquals("EXPLORATORY_MOTION_SYMMETRY", r.symmetry.label)
        val s = r.series!!
        assertEquals(s.t.size, s.speed.size); assertEquals(s.t.size, s.gait.size); assertEquals(s.t.size, s.lat.size)
        val g = r.girth!!
        assertTrue(g.t.isNotEmpty()); assertEquals(g.t.size, g.cadenceHz.size); assertEquals(g.t.size, g.status.size)
        // synchronised lookup by time, as the charts do
        val tTrot = (trot.t0 + trot.t1) / 2
        assertEquals(3.5, r.gnssAt(s.speed, tTrot), 0.2)
        assertEquals("TROT", r.gaitAt(tTrot)!!.code)
        val k = r.girthAt(tTrot)
        assertNotNull(k)
        assertEquals(1.45, g.cadenceHz[k!!], 0.05)
    }

    @Test fun realFirmwareFileAgreesWithTheKotlinAnalyser() {
        val r = EquineResult.parse(text("equine/sample_analysis.json"))
        assertEquals("SA1B2_000123_001", r.sessionId)
        // the engine keeps the previous app rule as "distancia_puenteada": both implementations must agree
        val kotlin = TrainingAnalyzer.analyze(listOf({ ByteArrayInputStream(TestRes.bytes("sample.avr")) }))
        assertEquals(kotlin.distanceM, r.metric("distancia_puenteada")!!.value, 0.05)
        assertEquals(kotlin.maxSpeedMs, r.metric("velocidad_maxima")!!.value, 1e-6)
        // the girth part of this file is too short for a cadence window: nothing is invented
        assertTrue(r.performance.segments.all { it.cadenceHz == null })
        assertEquals(100_000L, r.itow0Ms)
        assertEquals(0.0, r.timeOfItow(100_000L)!!, 1e-9)
    }

    @Test fun errorsAndComparisonFormat() {
        try { EquineResult.parse("{\"error\":\"no es un fichero AVO RAW válido: x\",\"codigo\":1}"); throw AssertionError("debería fallar") }
        catch (e: IllegalStateException) { assertTrue(e.message!!.contains("AVO RAW")) }
        val c = EqComparison.parse("""{"formato":"avo-equine-comparison","version":"1.1.0","sesion_a":"A","sesion_b":"B","comparable":false,"motivos":["aire dominante distinto: TROTE / GALOPE"],
            "diferencias":[{"metrica":"cadencia","unidad":"Hz","a":1.4,"b":1.9,"diferencia":0.5,"comparable":false,"contexto":"aires distintos"}],
            "recorrido":{"intentado":true,"comparable":false,"motivo":"x","separacion_mediana_m":40,"cobertura":1,"monotonia":1,"diferencia_velocidad_media":null,"diferencia_tiempo_total_s":null,"perfil":{"s":[],"velocidad_a":[],"velocidad_b":[],"diferencia_tiempo_s":[]}},
            "patron":{"calculado":true,"distancia_dtw_m_s":0.2,"deformacion":1.1,"nota":"n"},"curvas_equivalentes":[]}""")
        assertFalse(c.comparable); assertFalse(c.diffs[0].comparable); assertEquals(40.0, c.route.medianXtrackM!!, 1e-9)
        assertTrue(MiniJson.parse("[1,\"\\u00e9\",null,true]") is List<*>)
    }
}
