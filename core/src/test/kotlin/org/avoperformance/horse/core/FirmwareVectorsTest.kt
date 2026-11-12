package org.avoperformance.horse.core

import org.avoperformance.horse.core.auth.WatchAuth
import org.avoperformance.horse.core.ble.BleFlags
import org.avoperformance.horse.core.ble.BleFraming
import org.avoperformance.horse.core.ble.BleReassembler
import org.avoperformance.horse.core.ble.GeofenceState
import org.avoperformance.horse.core.ble.MsgType
import org.avoperformance.horse.core.ble.Requests
import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.ble.TimeSource
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.config.ExitAction
import org.avoperformance.horse.core.config.WatchConfig
import org.avoperformance.horse.core.geo.Fence
import org.avoperformance.horse.core.geo.FenceType
import org.avoperformance.horse.core.rtcm.RtcmFramer
import org.avoperformance.horse.core.telemetry.RtkDeriver
import org.avoperformance.horse.core.telemetry.RtkState
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Byte-exact cross-checks against vectors produced by the firmware's own C++ encoders (test/gen_vectors.cpp). */
class FirmwareVectorsTest {
    private val v = "vectors.txt"

    @Test fun fragmentsMatchFirmware() {
        val msg = TestRes.hex(v, "frag_msg")
        val frags = BleFraming.fragment(MsgType.SET_FENCE.code, 0x1234, msg, 64, BleFlags.ACK_REQ)
        assertEquals(TestRes.kv(v)["frag_count"]!!.toInt(), frags.size)
        for (i in frags.indices) assertArrayEquals(TestRes.hex(v, "frag_$i"), frags[i])
        // and the reassembler rebuilds the message
        val r = BleReassembler()
        var out: ByteArray? = null
        for (i in frags.indices) r.feed(TestRes.hex(v, "frag_$i"))?.let { out = it.payload }
        assertArrayEquals(msg, out)
    }

    @Test fun corruptedFragmentIsRejected() {
        val f = TestRes.hex(v, "frag_0")
        f[12] = (f[12].toInt() xor 0x01).toByte()
        val r = BleReassembler()
        assertEquals(null, r.feed(f))
        assertEquals(1, r.crcErrors)
    }

    @Test fun rtcmWriteMatchesFirmware() {
        val frame = TestRes.hex(v, "rtcm_frame")
        assertArrayEquals(TestRes.hex(v, "rtcm_ble_write"), Requests.rtcmWrite(7, frame, 0, frame.size, 0x0102))
        // Kotlin RTCM builder == firmware rtcm_build()
        val payload = ByteArray(20).also { it[0] = 0x43; it[1] = 0x50 }
        assertArrayEquals(frame, RtcmFramer.build(payload))
        assertEquals(1077, RtcmFramer().feed(frame).single().messageType)
    }

    @Test fun configDecodeAndReencodeIsByteExact() {
        val blob = TestRes.hex(v, "config")
        val r = WatchConfig.decode(blob)
        assertTrue(r is WatchConfig.Companion.Result.Ok)
        val c = (r as WatchConfig.Companion.Result.Ok).config
        assertEquals("CHALECO-01", c.deviceName)
        assertEquals(1L, c.horseId); assertEquals("HORSE_001", c.horseName)
        assertEquals(77L, c.riderId); assertEquals("RIDER_007", c.riderName)
        assertEquals(0x03, c.activeMask); assertEquals(7, c.entryConfirmS); assertEquals(20, c.exitConfirmS)
        assertEquals(400L, c.entryMarginCm); assertEquals(1200L, c.exitMarginCm); assertEquals(800L, c.hAccMaxCm)
        assertEquals(ExitAction.PAUSE, c.exitAction); assertEquals(25, c.preS); assertEquals(10, c.postS)
        assertEquals(2, c.fenceCount)
        assertEquals(FenceType.CIRCLE, c.fences[0]!!.type); assertEquals("TEST_CIRCULO", c.fences[0]!!.name)
        assertEquals(15000L, c.fences[0]!!.radiusCm)
        assertEquals(FenceType.POLYGON, c.fences[1]!!.type); assertEquals(4, c.fences[1]!!.vertices.size)
        assertEquals(460800L, c.uartBaud); assertEquals(3400, c.criticalBattMv)
        assertTrue(c.lines[0].enabled); assertEquals(1, c.lines[0].aLatE7); assertEquals(-2, c.lines[0].bLonE7)
        assertArrayEquals(blob, c.encode())
        assertTrue(c.problems().isEmpty())
    }

    @Test fun configRejectsBadCrc() {
        val blob = TestRes.hex(v, "config")
        blob[20] = (blob[20].toInt() xor 0xFF).toByte()
        assertTrue(WatchConfig.decode(blob) is WatchConfig.Companion.Result.Error)
    }

    @Test fun editingOneFieldKeepsTheRest() {
        val c = (WatchConfig.decode(TestRes.hex(v, "config")) as WatchConfig.Companion.Result.Ok).config
        val c2 = (WatchConfig.decode(c.copy(brightness = 120).encode()) as WatchConfig.Companion.Result.Ok).config
        assertEquals(120, c2.brightness)
        assertEquals(c.copy(brightness = 120), c2)
    }

    @Test fun fencesMatchFirmware() {
        val poly = TestRes.hex(v, "fence_poly")
        val circle = TestRes.hex(v, "fence_circle")
        val p = Fence.decodeBody(poly)!!
        val c = Fence.decodeBody(circle)!!
        assertArrayEquals(poly, p.encodeBody())
        assertArrayEquals(circle, c.encodeBody())
        assertEquals(null, p.validate())
        assertEquals(null, c.validate())
    }

    /** The map preview must take the same inside/outside decision as the watch (avo_geo.cpp CompiledFence). */
    @Test fun signedDistanceMatchesFirmware() {
        val c = (WatchConfig.decode(TestRes.hex(v, "config")) as WatchConfig.Companion.Result.Ok).config
        for (k in 0..1) {
            val f = c.fences[k]!!
            val pts = TestRes.kv(v)["sd_$k"]!!.split(';').filter { it.isNotBlank() }
            assertEquals(49, pts.size)
            for (p in pts) {
                val (la, lo, d) = p.split(',')
                assertEquals(d.toDouble(), f.signedDistanceM(org.avoperformance.horse.core.geo.GeoPoint(la.toInt(), lo.toInt())), 1e-3)
            }
        }
        val h = org.avoperformance.horse.core.geo.haversineM(
            org.avoperformance.horse.core.geo.GeoPoint(433800000, -32170000), org.avoperformance.horse.core.geo.GeoPoint(434100000, -34200000))
        assertEquals(TestRes.kv(v)["hav"]!!.toDouble(), h, 1e-3)
    }

    @Test fun telemetryV2DecodesFirmwareEncoding() {
        val b = TestRes.hex(v, "telemetry_v2")
        assertEquals(Telemetry.V2_LEN, b.size)
        val t = Telemetry.decode(b)!!
        assertEquals(WatchSessionState.RECORDING, t.session)
        assertEquals(GeofenceState.RECORDING, t.geofence)
        assertEquals(2, t.carrSoln); assertEquals(27, t.numSv); assertEquals(14L, t.hAccMm)
        assertEquals(433800123, t.latE7); assertEquals(-32170456, t.lonE7)
        assertEquals(8765, t.speedMmS); assertEquals(123456L, t.distanceCm); assertEquals(654321L, t.activeMs)
        assertEquals(87, t.batteryPct); assertEquals(3L, t.droppedRecords)
        val v2 = t.v2!!
        assertTrue(v2.gnssFixOk); assertTrue(v2.diffSoln); assertFalse(v2.invalidLlh); assertTrue(v2.haveGnss); assertTrue(v2.qualityOk)
        assertEquals(2, v2.corrAgeCode); assertEquals(3912, v2.backBatteryMv); assertEquals(TimeSource.GNSS, v2.timeSource)
        assertEquals(99999L, v2.rtcmToBackBytes); assertEquals(1234L, v2.rtcmUsedByReceiver); assertEquals(4012, v2.batteryMv)
        assertEquals(85L, v2.gnssAgeMs); assertEquals(25L, v2.vAccMm); assertEquals(40L, v2.linkAgeMs); assertEquals(5L, v2.girthLost)
        val rtk = RtkDeriver.derive(t, 100)
        assertEquals(RtkState.FIX, rtk.state)
        assertEquals(27, rtk.satellites)
        assertEquals(2000L, rtk.correctionAgeMaxMs)
        assertEquals(0.014, rtk.hAccM!!, 1e-9)
        // v1 watch (first 45 bytes only): still decodes, no v2 block
        val t1 = Telemetry.decode(b.copyOf(Telemetry.V1_LEN))!!
        assertEquals(null, t1.v2)
        assertEquals(RtkState.FIX, RtkDeriver.derive(t1, 100).state)
        // stale telemetry is never shown as FIX
        assertEquals(RtkState.DESCONOCIDO, RtkDeriver.derive(t, 5000).state)
    }

    /** Bytes produced by the CHEST 3.7.6 encoder (avo_ble_proto.cpp encode_telemetry) for a known v3 telemetry. */
    @Test fun telemetryV3DecodesFirmwareEncoding() {
        val hex = "00000000011b8c000000bb43db19281e15fe000000000000000000000000ff0000000000000000000000000000000000ff00000000000000000000000003000000ffffffff00000000ffffffff000000000000031f1b3a322c301a1605291c31010103005f00c0270900c8af00003e0000007600"
        val b = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        assertEquals(Telemetry.V3_LEN, b.size)
        val t = Telemetry.decode(b)!!
        assertEquals(1, t.carrSoln); assertEquals(27, t.numSv); assertEquals(433800123, t.latE7)
        val q = t.v3!!
        assertTrue(q.backHasQuality); assertTrue(q.signalsFresh); assertFalse(q.l1Only)
        assertEquals(31, q.svTracked); assertEquals(27, q.svUsed); assertEquals(58, q.sigTracked); assertEquals(50, q.sigUsed)
        assertEquals(44, q.sigCarrierUsed); assertEquals(48, q.sigCorrected); assertEquals(26, q.sigL2); assertEquals(22, q.sigL2Used)
        assertEquals(5, q.sigWeak); assertEquals(41, q.cnoMean); assertEquals(28, q.cnoMin); assertEquals(49, q.cnoMax)
        assertEquals(1, q.qualityAgeS); assertEquals(1, q.qualityMon); assertEquals(3, q.fixLost); assertEquals(95, q.firstFixS)
        assertEquals(600000L, q.fixedMs); assertEquals(45000L, q.floatMs); assertEquals(62L, q.sAccMmS); assertEquals(118, q.pdopE2)
        // L1-only antenna: signals tracked, none on the second band
        assertTrue(q.copy(sigL2 = 0, sigL2Used = 0).l1Only)
        // older watch (v2 length): no v3 block
        assertEquals(null, Telemetry.decode(b.copyOf(Telemetry.V2_LEN))!!.v3)
    }

    @Test fun rtkStatesFromReceiverFlags() {
        val t = Telemetry.decode(TestRes.hex(v, "telemetry_v2"))!!
        assertEquals(RtkState.FLOAT, RtkDeriver.derive(t.copy(carrSoln = 1), 0).state)
        assertEquals(RtkState.DGNSS, RtkDeriver.derive(t.copy(carrSoln = 0), 0).state)
        assertEquals(RtkState.AUTONOMO, RtkDeriver.derive(t.copy(carrSoln = 0, v2 = t.v2!!.copy(gnssFlags = 0x19)), 0).state)
        assertEquals(RtkState.SIN_GNSS, RtkDeriver.derive(t.copy(v2 = t.v2!!.copy(gnssAgeMs = null)), 0).state)
        assertEquals(RtkState.SIN_GNSS, RtkDeriver.derive(t.copy(fixType = 0), 0).state)
        assertEquals(RtkState.SIN_GNSS, RtkDeriver.derive(t.copy(v2 = t.v2!!.copy(gnssFlags = 0x1C)), 0).state)
    }

    @Test fun authProofsMatchFirmware() {
        val a = "vectors_auth.txt"
        val kv = TestRes.kv(a)
        val key = TestRes.hex(a, "key"); val pn = TestRes.hex(a, "pn"); val wn = TestRes.hex(a, "wn")
        assertArrayEquals(TestRes.hex(a, "watch_proof"), WatchAuth.watchProof(key, pn, wn, kv["dev_id"]!!))
        assertArrayEquals(TestRes.hex(a, "phone_proof"), WatchAuth.phoneProof(key, wn, pn, kv["dev_id"]!!))
        assertFalse(WatchAuth.same(WatchAuth.phoneProof(key, wn, pn, "A1B2C3D4E5F7"), TestRes.hex(a, "phone_proof")))
        assertNotNull(WatchAuth.nonce())
        assertEquals(16, WatchAuth.nonce().size)
    }
}
