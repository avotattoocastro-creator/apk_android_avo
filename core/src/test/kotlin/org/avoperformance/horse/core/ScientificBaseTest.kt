package org.avoperformance.horse.core

import org.avoperformance.horse.core.engine.EquineResult
import org.avoperformance.horse.core.engine.KbFormat
import org.avoperformance.horse.core.engine.KbHistory
import org.avoperformance.horse.core.engine.KbRule
import org.avoperformance.horse.core.engine.KbSession
import org.avoperformance.horse.core.engine.J
import org.avoperformance.horse.core.engine.MiniJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Base científica KB-1 (pantalla «Base científica»): JSON del motor -> modelo Kotlin.
 * kb_psi_analysis.json y kb_training_history_psi.json son SINTÉTICOS (motor 2.0.0-dev26, KB-1 1.24.0; generador en
 * scripts/fixtures/gen_kb_fixtures.cpp). synthetic_analysis.json y sample_analysis.json traen el bloque sin ritmo de
 * carrera (perfil GENERICO). Verifican la cadena, no la exactitud con caballos reales.
 */
class ScientificBaseTest {
    private fun text(name: String) = String(TestRes.bytes(name), Charsets.UTF_8)

    @Test fun sessionBlockOfPsiTraining() {
        val r = EquineResult.parse(text("equine/kb_psi_analysis.json"))
        val kb = r.scientificBase!!
        assertEquals("PSI", kb.breed)
        assertEquals(16.7, kb.racePace!!, 1e-9)
        assertEquals("RAZA", kb.racePaceOrigin)
        assertEquals(listOf("B1_TRABAJO", "B2_INTERMEDIA", "B3_ALTA"), kb.bands.map { it.code })
        assertEquals("11,0–13,4 m/s", kb.bands[0].limitsText)
        assertEquals("≥ 15,5 m/s", kb.bands[2].limitsText)
        assertEquals(681.676, kb.bands[2].distanceM!!, 1e-3)
        assertEquals(341.075, kb.canterM!!, 1e-3)
        assertEquals(811.3, kb.gallopM!!, 1e-3)
        assertEquals(14.0, kb.gallopCut!!, 1e-9)
        assertEquals(5.76141, kb.bonePct!!, 1e-5)
        assertEquals(0.160781, kb.boneLowPct!!, 1e-6)
        assertEquals(true, kb.calibrated)
        assertEquals(1, kb.final600.size)
        assertEquals(16.0174, kb.final600[0].speed!!, 1e-4)
        assertEquals("Trabajo 1", kb.final600[0].title)
    }

    @Test fun fixturesWithoutRacePaceAreNoData() {
        for (f in listOf("equine/synthetic_analysis.json", "equine/sample_analysis.json")) {
            val kb = EquineResult.parse(text(f)).scientificBase!!
            assertNull(kb.racePace)
            assertEquals("SIN_REFERENCIA", kb.racePaceOrigin)
            assertNull(kb.canterM)
            assertNull(kb.gallopM)
            assertEquals(KbFormat.NO_DATA, KbFormat.metres(kb.gallopM))
            assertEquals(KbFormat.NO_DATA, kb.bands[1].limitsText)
            assertEquals(false, kb.calibrated)
            assertTrue(kb.final600.isEmpty())
        }
        // análisis anterior a KB-1: sin bloque
        assertNull(KbSession.fromTrackWork(J(MiniJson.parse("""{"perfil":{"raza":"PSI"}}"""))))
    }

    @Test fun historyStatusAndRules() {
        val kb = KbHistory.fromTrainingAnalysis(text("equine/kb_training_history_psi.json"))!!
        assertTrue(kb.available)
        assertEquals("1.24.0", kb.version)
        assertTrue(kb.d30!!.canterM!! > 44_000)
        assertTrue(kb.d30!!.gallopM!! > 6_000)
        assertNotNull(kb.d7); assertNotNull(kb.prev30); assertNotNull(kb.d60)
        assertEquals(0, kb.daysWithoutFastWork)
        assertNull(kb.returnDay)
        assertNotNull(kb.gallopRatio)
        assertNotNull(kb.boneRatio7d)
        assertEquals(setOf("A1_CANTER_30D", "A2_GALOPE_30D", "A3_RAMPA", "KB_FATIGA_OSEA_7D"), kb.rules.map { it.rule }.toSet())
        val a1 = kb.rule("A1_CANTER_30D")!!
        assertEquals("VIGILAR", a1.level)
        assertTrue(a1.isLimit)
        assertTrue(a1.evidence.contains("Verheyen 2006"))
        assertEquals("A1", a1.code)
        assertEquals("AVISO", kb.rule("KB_FATIGA_OSEA_7D")!!.action)
        assertEquals("FO 7 d", KbRule.codeOf("KB_FATIGA_OSEA_7D"))
        // cada sesión de la historia trae su propio estado
        val last = J(MiniJson.parse(text("equine/kb_training_history_psi.json")))["sesiones"].list.last()
        assertTrue(KbHistory.of(last["base_cientifica"])!!.available)
    }

    @Test fun historyNullsStayNull() {
        val kb = KbHistory.of(J(MiniJson.parse("""{"version":"1.24.0","disponible":true,"d7":{"bandas_m":[null,0,0],"canter_m":null,"sesiones":0,
            "sesiones_sin_datos":2},"fatiga_osea_ratio_7d":null,"dias_sin_trabajo_rapido":null,"cociente_galope":null,
            "vuelta_descanso":{"dia":3,"dias_sin_rapido_antes":95},"reglas":[]}""")))!!
        assertNull(kb.d7!!.bandsM[0])
        assertNull(kb.d7!!.canterM)
        assertEquals(2, kb.d7!!.sessionsWithoutData)
        assertNull(kb.d30)
        assertNull(kb.boneRatio7d)
        assertNull(kb.daysWithoutFastWork)
        assertNull(kb.gallopRatio)
        assertEquals(3, kb.returnDay)
        assertEquals(95, kb.returnRestDays)
        assertFalse(kb.rules.isNotEmpty())
        assertEquals("Día 3.", KbFormat.sentence("día 3"))
        assertNull(KbHistory.of(J(null)))
    }
}
