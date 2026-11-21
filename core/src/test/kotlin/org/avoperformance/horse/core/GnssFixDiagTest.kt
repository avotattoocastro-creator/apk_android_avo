package org.avoperformance.horse.core

import org.avoperformance.horse.core.telemetry.FixSeverity
import org.avoperformance.horse.core.telemetry.GnssFixDiag
import org.avoperformance.horse.core.telemetry.GnssFixInput
import org.avoperformance.horse.core.telemetry.RtcmFamilies
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Diagnóstico de «no hay RTK FIX» a partir del DIAG del pecho 3.7.11 (BackStatus v4 de la espalda 3.15.0). */
class GnssFixDiagTest {
    private fun diag(extra: String = "") = ("back_fw=3.15.0 rf_ant=2 rf_pwr=1 rf_jam=1 rf_jam1=10 rf_jam2=12 rf_agc1=55 rf_agc2=60 " +
        "rf_noise1=80 rf_noise2=90 rf_age=3 rtcm_types=${RtcmFamilies.BASE_POS or RtcmFamilies.GPS_MSM or RtcmFamilies.GAL_MSM or RtcmFamilies.GLO_MSM or RtcmFamilies.GLO_BIAS or RtcmFamilies.MSM7} " +
        "rtcm_used=${RtcmFamilies.GPS_MSM or RtcmFamilies.GAL_MSM or RtcmFamilies.GLO_MSM or RtcmFamilies.MSM7} base_id=2003 base_dam=850 dyn=7 gnss_set=15 " +
        "sv=28 sv_used=25 sig=52 sig_used=46 sig_cr=40 sig_corr=44 sig_l2=22 sig_l2_used=20 cno=44 cno_min=30 cno_max=50 " +
        "fix_lost=0 ttff_fix=65535 fixed_s=0 float_s=0 $extra").trim().split(' ').associate { it.substringBefore('=') to it.substringAfter('=') }

    private fun blocking(m: Map<String, String>, carr: Int? = 0) =
        GnssFixDiag.analyze(GnssFixInput.from(m), carr, true).findings.filter { it.severity == FixSeverity.BLOQUEA }.map { it.text }

    @Test fun buenaConfiguracionSinBloqueos() {
        val r = GnssFixDiag.analyze(GnssFixInput.from(diag()), 1, true)
        assertTrue(r.findings.none { it.severity == FixSeverity.BLOQUEA })
        assertTrue(r.rows.any { it.label == "Estación base" && it.value.contains("8.5 km") })
        assertTrue(r.rows.any { it.label == "Correcciones recibidas" && it.value.contains("GLONASS") })
    }

    @Test fun nocheEnCasaSenalDebilSinFase() {
        // campo 20/11/2026: C/N0 media 33, 0 señales con fase portadora
        val b = blocking(diag("cno=33 sig_cr=0"))
        assertTrue(b.any { it.contains("Señal débil") })
        assertTrue(b.any { it.contains("fase de portadora") })
    }

    @Test fun antenaDeUnaBanda() {
        assertTrue(blocking(diag("sig_l2=0 sig_l2_used=0")).any { it.contains("segunda banda") })
    }

    @Test fun antenaAbiertaOCorto() {
        assertTrue(blocking(diag("rf_ant=4")).any { it.contains("ABIERTA") })
        assertTrue(blocking(diag("rf_ant=3")).any { it.contains("CORTOCIRCUITO") })
        assertTrue(blocking(diag("rf_jam=3")).any { it.contains("CRÍTICA") })
    }

    @Test fun basesYCorrecciones() {
        assertTrue(blocking(diag("rtcm_types=${RtcmFamilies.GPS_MSM or RtcmFamilies.MSM7}")).any { it.contains("1005/1006") })
        assertTrue(blocking(diag("rtcm_types=${RtcmFamilies.BASE_POS or RtcmFamilies.GPS_LEGACY or RtcmFamilies.GLO_LEGACY} rtcm_used=0")).any { it.contains("antiguos") })
        assertTrue(blocking(diag("rtcm_types=${RtcmFamilies.BASE_POS or RtcmFamilies.GPS_MSM or RtcmFamilies.MSM123}")).any { it.contains("MSM1-3") })
        assertTrue(blocking(diag("rtcm_used=0")).any { it.contains("no usa ninguna") })
        assertTrue(blocking(diag("rtcm_types=0")).any { it.contains("ninguna corrección") })
        assertTrue(blocking(diag("base_dam=4200")).any { it.contains("42.0 km") })
    }

    @Test fun sinBloqueV4() {
        val m = mapOf("back_fw" to "3.14.7", "cno" to "33", "sig" to "40", "sig_used" to "30", "sig_cr" to "0")
        val r = GnssFixDiag.analyze(GnssFixInput.from(m), 0, null)
        assertFalse(GnssFixInput.from(m).hasV4)
        assertTrue(r.findings.any { it.text.contains("3.15.0") })
    }

    @Test fun desconocidosNoCuentan() {
        val i = GnssFixInput.from(diag("rf_ant=255 base_dam=65535 base_id=65535"))
        assertEquals(null, i.rfAnt); assertEquals(null, i.baseDistDam); assertEquals(null, i.baseId)
    }

    @Test fun nombresDeFamilias() {
        assertEquals("ninguna", RtcmFamilies.describe(0))
        assertEquals(listOf("GPS", "Galileo"), RtcmFamilies.constellations(RtcmFamilies.GPS_MSM or RtcmFamilies.GAL_MSM or RtcmFamilies.BASE_POS))
        // mismos bits que avo_payloads.h (RtcmTypeBit) y el vector compartido 0x101F
        assertEquals("posición de la base (1005/1006), GPS, GLONASS, Galileo, BeiDou, MSM7", RtcmFamilies.describe(0x101F))
    }
}
