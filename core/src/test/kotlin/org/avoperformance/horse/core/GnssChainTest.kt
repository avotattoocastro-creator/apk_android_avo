package org.avoperformance.horse.core

import org.avoperformance.horse.core.ble.DiagParser
import org.avoperformance.horse.core.telemetry.GnssChain
import org.avoperformance.horse.core.telemetry.GnssDiagSnapshot
import org.avoperformance.horse.core.telemetry.StageState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 2.14-gnss: RTCM / UBX chain from the DIAG_GET text of the watch (format of ble_service.cpp, CHEST 3.5.0+). */
class GnssChainTest {
    private fun diag(rtcmIn: Long, rtcmOut: Long, backRx: Long, toZed: Long, used: Long, ubx: Long, bad: Long = 0, fail: Long = 0, age: Long = 400) =
        "fw=3.7.10 src=abc boot=3 reset=POWERON up=120s heap=100000 psram=1000 sd=1 rec=BUFFER TEMPORAL ring=0% drop=0 " +
            "uart=1 ok=10 crc=0 lost=0 rtcm_in=$rtcmIn rtcm_out=$rtcmOut rtcm_drop=0 zed_used=$used girth=0 imu=0 gnss_hz=8.0 " +
            "batt=80% 3900mV time=GNSS safe=0 largest=1 psram_min=1 heap_min=1 keys=1 auth_fail=0 mtu=247 " +
            "link=espnow now_paired=1 now_pairing=0 now_peer=AA:BB:CC:DD:EE:FF now_tx_ok=1 now_tx_fail=0 now_retry=0 now_rx=1 " +
            "now_foreign=0 now_bad=0 now_rssi=-50 rtcm_nolink=0 ble_rtcm_rejected=0 back_status_age_ms=$age " +
            "back_fw=3.14.4 zed=FUNCIONANDO zed_baud=230400 zed_port=2 zed_cfg=3 nav_hz_cfg=8 back_gnss_hz=8.0 " +
            "back_rtcm_rx=$backRx back_rtcm_zed=$toZed back_rtcm_ok=10 back_rtcm_bad=$bad back_rtcm_gap=0 back_rtcm_nowr=0 " +
            "zed_used=$used zed_fail=$fail ubx=$ubx nmea=0 back_tx_fail=0 back_rssi=-48"

    private fun snap(t: Long, caster: Long, phone: Long, d: String) = GnssDiagSnapshot.from(DiagParser.parse(d), t, caster, phone)

    @Test fun parsesTheWatchDiagText() {
        val s = snap(0, 100, 90, diag(80, 70, 60, 50, 7, 1234))
        assertEquals(80L, s.watchRtcmIn); assertEquals(70L, s.watchRtcmOut); assertEquals(60L, s.backRtcmRx)
        assertEquals(50L, s.backRtcmToZed); assertEquals(7L, s.zedUsed); assertEquals(1234L, s.ubxFrames)
        assertEquals("FUNCIONANDO", s.zedState); assertEquals(230400L, s.zedBaud); assertEquals(400L, s.backStatusAgeMs)
    }

    @Test fun everyStageMovingMeansCorrectionsUsedButNotFix() {
        val a = snap(0, 10_000, 9_000, diag(8_000, 7_000, 7_000, 7_000, 100, 1000))
        val b = snap(5_000, 17_500, 16_500, diag(15_500, 14_500, 14_500, 14_500, 140, 1100))
        val r = GnssChain.report(a, b, true)!!
        assertTrue(r.rtcm.take(7).all { it.state == StageState.OK })
        assertEquals(StageState.OK, r.rtcmVerdictState)
        assertTrue(r.rtcmVerdict.contains("no implica RTK FIX"))
        assertEquals(StageState.OK, r.ubx.state)
        assertTrue(r.ubx.value!!.startsWith("20.0 tramas/s"))
    }

    @Test fun findsWhereTheCorrectionsStop() {
        // phone sends, watch receives, but nothing reaches the back
        val a = snap(0, 10_000, 9_000, diag(8_000, 7_000, 7_000, 7_000, 100, 1000))
        val b = snap(5_000, 17_500, 16_500, diag(15_500, 7_000, 7_000, 7_000, 100, 1100))
        val r = GnssChain.report(a, b, true)!!
        assertEquals(StageState.PARADO, r.rtcmVerdictState)
        assertTrue(r.rtcmVerdict, r.rtcmVerdict.contains("Reloj → espalda"))
        // receiver gets the bytes but does not use them
        val c = snap(5_000, 17_500, 16_500, diag(15_500, 14_500, 14_500, 14_500, 100, 1100))
        val r2 = GnssChain.report(a, c, true)!!
        assertTrue(r2.rtcmVerdict, r2.rtcmVerdict.contains("Usadas por el receptor"))
    }

    @Test fun lossesAreListed() {
        val a = snap(0, 1, 1, diag(1, 1, 1, 1, 1, 1, bad = 2, fail = 0))
        val b = snap(3_000, 2, 2, diag(2, 2, 2, 2, 2, 2, bad = 5, fail = 4))
        val r = GnssChain.report(a, b, true)!!
        val loss = r.rtcm.first { it.name == "Pérdidas" }
        assertEquals(StageState.ERROR, loss.state)
        assertTrue(loss.value!!.contains("CRC")); assertFalse(loss.value!!.contains("rechaza"))
        val unused = r.rtcm.last()
        assertEquals("No usadas por el receptor", unused.name)
        assertEquals(StageState.PARADO, unused.state)          // information, not an error
        assertTrue(unused.value!!.startsWith("1.3 msg/s"))
    }

    @Test fun staleBackStatusIsNotPresentedAsCurrent() {
        val a = snap(0, 1, 1, diag(1, 1, 1, 1, 1, 1, age = 9_000))
        val b = snap(3_000, 2, 2, diag(2, 2, 2, 2, 2, 2, age = 12_000))
        val r = GnssChain.report(a, b, true)!!
        assertEquals(StageState.SIN_DATOS, r.rtcmVerdictState)
        assertEquals(StageState.SIN_DATOS, r.ubx.state)
        assertNull(r.rtcm[4].value)   // back counters hidden
    }

    @Test fun ntripIdleAndFirstSnapshot() {
        val b = snap(3_000, 0, 0, diag(0, 0, 0, 0, 0, 10))
        val r = GnssChain.report(null, b, false)!!
        assertTrue(r.rtcmVerdict.startsWith("NTRIP sin datos"))
        assertNull(GnssChain.report(null, null, true))
        // counter reset (back rebooted) gives no negative rate
        val a = snap(0, 0, 0, diag(0, 0, 0, 900, 0, 5000))
        val r2 = GnssChain.report(a, b, false)!!
        assertNotNull(r2.rtcm[5].value)
        assertFalse(r2.rtcm[5].value!!.contains("-"))
    }

    @Test fun speedTarget() {
        assertTrue(GnssChain.speedTargetMet(55))     // 0.198 km/h
        assertFalse(GnssChain.speedTargetMet(56))    // 0.2016 km/h
        assertFalse(GnssChain.speedTargetMet(144))   // 0.52 km/h (field 20/11/2026)
        assertFalse(GnssChain.speedTargetMet(0))     // not reported
    }
}
