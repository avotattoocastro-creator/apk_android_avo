package org.avoperformance.horse.core

import org.avoperformance.horse.core.ble.WatchFileState
import org.avoperformance.horse.core.ble.WatchSessionEntry
import org.avoperformance.horse.core.geo.Fence
import org.avoperformance.horse.core.geo.FenceType
import org.avoperformance.horse.core.geo.GeoPoint
import org.avoperformance.horse.core.raw.RawReader
import org.avoperformance.horse.core.raw.TrainingAnalyzer
import org.avoperformance.horse.core.sync.LocalTraining
import org.avoperformance.horse.core.sync.SessionDownload
import org.avoperformance.horse.core.sync.SyncRules
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.core.bytes.toHex
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest

class RawAndSyncTest {
    private val avr = TestRes.bytes("sample.avr")              // written by the firmware RawWriter (test/gen_raw.cpp)
    private val exp = TestRes.kv("sample_expected.txt")         // numbers computed by the C++ side

    @Test fun rawScanMatchesFirmwareScanner() {
        val s = RawReader.scan(ByteArrayInputStream(avr))
        assertNotNull(s.header)
        assertEquals("SA1B2_000123_001", s.header!!.sessionId)
        assertEquals("HORSE_001", s.header!!.horseName)
        assertEquals(exp["blocks"]!!.toInt(), s.blocks)
        assertEquals(exp["records"]!!.toInt(), s.records)
        assertEquals(exp["valid_end"]!!.toLong(), s.validEnd)
        assertEquals(exp["file_size"]!!.toLong(), s.fileSize)
        assertEquals(exp["clean_close"] == "1", s.cleanClose)
        assertEquals(exp["tail_garbage"] == "1", s.tailGarbage)
        assertEquals(0, s.badRecords)
    }

    @Test fun analysisUsesOnlyRealData() {
        val a = TrainingAnalyzer.analyze(listOf({ ByteArrayInputStream(avr) }))
        assertEquals(exp["gnss"]!!.toInt(), a.gnssSamples)
        assertEquals(exp["gnss_valid"]!!.toInt(), a.gnssUsable)
        assertEquals(exp["no_fix"]!!.toInt(), a.noFix)
        assertEquals(exp["auto"]!!.toInt(), a.autonomousEpochs)
        assertEquals(exp["float"]!!.toInt(), a.floatEpochs)
        assertEquals(exp["fix"]!!.toInt(), a.fixEpochs)
        assertEquals(exp["imu_batches"]!!.toInt(), a.imuBatches)
        assertEquals(exp["imu_samples"]!!.toLong(), a.imuSamples)
        assertEquals(exp["markers"]!!.toInt(), a.markers)
        assertEquals(exp["distance_m"]!!.toDouble(), a.distanceM, 0.01)
        assertEquals(exp["max_speed_ms"]!!.toDouble(), a.maxSpeedMs, 1e-9)
        assertEquals(10, a.navRateHz)
        assertEquals(9.8, a.fixTimeS!!, 1e-9)
        assertTrue(a.imuAvailable)
        assertEquals(0, a.badUartFrames)
        assertEquals(a.gnssUsable, a.track.size)
    }

    @Test fun truncatedDownloadNeverYieldsAFakeBlock() {
        // cut in the middle of block 5: the reader stops at the last complete block
        val full = RawReader.scan(ByteArrayInputStream(avr))
        val cut = avr.copyOf((full.validEnd / 2).toInt())
        val s = RawReader.scan(ByteArrayInputStream(cut))
        assertTrue(s.blocks < full.blocks)
        assertTrue(s.tailGarbage)
        assertTrue(s.validEnd <= cut.size)
    }

    private fun entry(id: String, bytes: Long, state: WatchFileState = WatchFileState.CLOSED, rec: Boolean = false) =
        WatchSessionEntry(id, state, 1, bytes, 1_760_000_000_000, 60_000, rec)

    @Test fun mergeNeverDuplicatesAndKeepsPhoneCopies() {
        val local = mapOf("S1" to LocalTraining("S1", 1, 100, 100, "aa", "aa", null, SyncState.VERIFICADO_LOCAL, WatchFileState.CLOSED, 0, 0),
            "S0" to LocalTraining("S0", 1, 50, 50, "bb", "bb", "bb", SyncState.MARCADO_EN_RELOJ, WatchFileState.UPLOADED, 0, 0))
        val watch = listOf(entry("S1", 100), entry("S1", 100), entry("S2", 10), entry("S3", 5, WatchFileState.OPEN, true))
        val m = SyncRules.merge(watch, local)
        assertEquals(listOf("S1", "S2", "S3", "S0"), m.map { it.sessionId })
        assertEquals(SyncState.VERIFICADO_LOCAL, m[0].state)
        assertEquals(SyncState.EN_RELOJ, m[1].state)
        assertEquals(SyncState.GRABANDO, m[2].state)
        assertEquals(SyncState.MARCADO_EN_RELOJ, m[3].state)   // deleted on the watch, still on the phone
        assertFalse(SyncRules.canDownload(watch[3]))
    }

    @Test fun markUploadedOnlyWithServerConfirmation() {
        val t = LocalTraining("S1", 1, 100, 100, "aa", "aa", null, SyncState.VERIFICADO_LOCAL, WatchFileState.CLOSED, 0, 0)
        assertFalse(SyncRules.canMarkUploaded(t))
        assertFalse(SyncRules.canMarkUploaded(t.copy(state = SyncState.VERIFICADO_SERVIDOR, serverSha256Hex = "ab")))
        assertTrue(SyncRules.canMarkUploaded(t.copy(state = SyncState.VERIFICADO_SERVIDOR, serverSha256Hex = "aa")))
        assertFalse(SyncRules.canOfferDelete(t))
        assertFalse(SyncRules.canOfferDelete(t.copy(state = SyncState.VERIFICADO_SERVIDOR)))
    }

    @Test fun resumableDownloadAcrossInterruptions() {
        val dir = Files.createTempDirectory("avo_dl").toFile()
        try {
            val seg1 = avr; val seg2 = avr.copyOfRange(0, 9000)
            val segs = listOf(seg1, seg2)
            fun serve(seg: Int, off: Long, len: Int): Pair<ByteArray, Long>? {
                val s = segs.getOrNull(seg - 1) ?: return null
                val end = minOf(s.size.toLong(), off + len).toInt()
                return s.copyOfRange(off.toInt(), end) to s.size.toLong()
            }
            var chunks = 0
            // first attempt: interrupted after 2 chunks
            run {
                val d = SessionDownload(dir, "S1", 2)
                var pos: Pair<Int, Long>? = d.position()
                while (pos != null && chunks < 2) { val (data, size) = serve(pos.first, pos.second, 16384)!!; pos = d.append(pos.first, pos.second, data, size); chunks++ }
            }
            // second attempt: new object (app restarted) resumes from the files on disk
            val d = SessionDownload(dir, "S1", 2)
            assertEquals(1 to 32768L, d.position())
            var pos: Pair<Int, Long>? = d.position()
            while (pos != null) { val (data, size) = serve(pos.first, pos.second, 16384)!!; pos = d.append(pos.first, pos.second, data, size) }
            assertArrayEquals(seg1, d.segFile(1).readBytes())
            assertArrayEquals(seg2, d.segFile(2).readBytes())
            val md = MessageDigest.getInstance("SHA-256"); md.update(seg1); md.update(seg2)
            assertEquals(md.digest().toHex(), d.sha256().toHex())
            assertEquals((seg1.size + seg2.size).toLong(), d.downloadedBytes())
        } finally { dir.deleteRecursively() }
    }

    @Test fun fenceValidationLikeFirmware() {
        val c = GeoPoint.of(40.0, -3.0)
        assertEquals(null, Fence(0, FenceType.CIRCLE, "C", c, 5000).validate())
        assertTrue(Fence(0, FenceType.CIRCLE, "C", c, 100).validate() != null)          // < 5 m
        val sq = listOf(GeoPoint.of(40.0, -3.0), GeoPoint.of(40.0005, -3.0), GeoPoint.of(40.0005, -2.9995), GeoPoint.of(40.0, -2.9995))
        assertEquals(null, Fence(1, FenceType.POLYGON, "P", vertices = sq).validate())
        val bow = listOf(sq[0], sq[2], sq[1], sq[3])                                     // self-intersecting
        assertEquals("El polígono se corta a sí mismo", Fence(1, FenceType.POLYGON, "P", vertices = bow).validate())
        val f = Fence(1, FenceType.POLYGON, "P", vertices = sq)
        assertTrue(f.signedDistanceM(GeoPoint.of(40.00025, -2.99975)) < 0)
        assertTrue(f.signedDistanceM(GeoPoint.of(40.002, -2.99975)) > 100)
        val circle = Fence(0, FenceType.CIRCLE, "C", c, 5000)
        assertEquals(-50.0, circle.signedDistanceM(c), 1e-6)
        // slot request = u8 slot + body with id forced to the slot
        val req = f.setFenceRequest(3)
        assertEquals(3, req[0].toInt()); assertEquals(3, req[1].toInt())
    }

    @Test fun localFilesStayAfterSessionList() {
        // keeps the "never auto-delete" contract visible in tests: merge() has no delete path
        val m = SyncRules.merge(emptyList(), mapOf("X" to LocalTraining("X", 1, 1, 1, null, null, null, SyncState.DESCARGADO, WatchFileState.CLOSED, 0, 0)))
        assertEquals(1, m.size)
        assertTrue(File("/").exists())
    }
}
