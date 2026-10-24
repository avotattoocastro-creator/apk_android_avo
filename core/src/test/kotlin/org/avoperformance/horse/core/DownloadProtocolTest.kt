package org.avoperformance.horse.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.avoperformance.horse.core.ble.AvoClient
import org.avoperformance.horse.core.ble.AvoGatt
import org.avoperformance.horse.core.ble.AvoTransport
import org.avoperformance.horse.core.ble.BleFlags
import org.avoperformance.horse.core.ble.BleFraming
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.MsgType
import org.avoperformance.horse.core.bytes.Crc
import org.avoperformance.horse.core.sync.ResilientDownload
import org.avoperformance.horse.core.sync.SessionDownload
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.nio.file.Files
import java.security.MessageDigest
import kotlin.random.Random

/**
 * READ_FILE download against a simulated watch that follows the firmware (V3.5.4+: at most 2048 B per reply,
 * offset + total size + CRC-32 header, FILE_DATA on FILE_TX, NOT_FOUND after the last segment), with injected faults.
 * Virtual time (kotlinx-coroutines-test): timeouts and pauses run instantly. Physical validation with the real
 * watch is still pending.
 */
class DownloadProtocolTest {
    enum class Fault { OK, DROP_ALL, DROP_FRAGMENT, DELAY_PAST_TIMEOUT, GATT_ERROR }

    /** Simulated watch: [segments] are the session files; [plan] decides the fault of the n-th READ_FILE. */
    class FakeWatch(val scope: CoroutineScope, val segments: List<ByteArray>, val att: Int = 244, val plan: (Int) -> Fault = { Fault.OK }) : AvoTransport {
        var clientOrNull: AvoClient? = null
        var client: AvoClient
            get() = clientOrNull ?: AvoClient(this, {}).also { clientOrNull = it }
            set(v) { clientOrNull = v }
        var reads = 0; var rtcmWrites = 0; var connected = true
        private val reasm = org.avoperformance.horse.core.ble.BleReassembler()
        override val attPayload get() = att
        override suspend fun writeRtcm(frag: ByteArray): Boolean { rtcmWrites++; return true }
        override suspend fun writeCtrl(frag: ByteArray) {
            if (!connected) throw IOException("Sin conexión con el reloj")
            val f = reasm.feed(frag) ?: return                       // requests may span several fragments at a small MTU
            if (f.type != MsgType.READ_FILE.code) return
            val fault = plan(reads++)
            if (fault == Fault.GATT_ERROR) throw IOException("Escritura BLE fallida (estado 133)")
            val p = f.payload
            val seg = u16(p, 24); val off = u32(p, 26); val len = u32(p, 30)
            val file = segments.getOrNull((if (seg == 0) 1 else seg) - 1)
            val frags: List<ByteArray> = if (file == null) {
                listOf(BleFraming.build(MsgType.FILE_DATA.code, f.msgId, 0, 1, BleFlags.RESPONSE or BleFlags.ERROR, BleStatus.NOT_FOUND.code, ByteArray(0)))
            } else {
                val n = minOf(len, 2048L, file.size - off).toInt()      // firmware cap (V3.5.4 SD FIX)
                val data = file.copyOfRange(off.toInt(), off.toInt() + n)
                val payload = le32(off) + le32(file.size.toLong()) + le32(Crc.crc32(data)) + data
                BleFraming.fragment(MsgType.FILE_DATA.code, f.msgId, payload, att, BleFlags.RESPONSE)
            }
            scope.launch {
                when (fault) {
                    Fault.DROP_ALL -> return@launch                                   // reply never leaves the watch
                    Fault.DELAY_PAST_TIMEOUT -> delay(9_000)                          // arrives after the 8 s timeout
                    else -> delay(5)
                }
                frags.forEachIndexed { i, fr -> if (!(fault == Fault.DROP_FRAGMENT && i == frags.size / 2)) client.onNotification(AvoGatt.FILE_TX, fr) }
            }
        }
        private fun u16(b: ByteArray, o: Int) = (b[o].toInt() and 0xFF) or ((b[o + 1].toInt() and 0xFF) shl 8)
        private fun u32(b: ByteArray, o: Int) = (0..3).fold(0L) { a, i -> a or ((b[o + i].toLong() and 0xFF) shl (8 * i)) }
        private fun le32(v: Long) = ByteArray(4) { ((v shr (8 * it)) and 0xFF).toByte() }
    }

    private fun session(sizes: List<Int>, seed: Int = 1) = sizes.map { Random(seed + it).nextBytes(it) }
    private fun sha(parts: List<ByteArray>) = MessageDigest.getInstance("SHA-256").apply { parts.forEach { update(it) } }.digest()

    private suspend fun CoroutineScope.download(w: FakeWatch, dir: java.io.File = Files.createTempDirectory("avo_dl").toFile(), client: () -> AvoClient? = { w.client }): SessionDownload {
        val dl = SessionDownload(dir, "S1E8C_000009_001", w.segments.size)
        ResilientDownload(client, pause = { delay(it) }).run("S1E8C_000009_001", dl)
        return dl
    }

    private fun check(dl: SessionDownload, parts: List<ByteArray>) {
        assertEquals(parts.sumOf { it.size }.toLong(), dl.downloadedBytes())
        parts.forEachIndexed { i, p -> assertArrayEquals("segmento ${i + 1}", p, dl.segFile(i + 1).readBytes()) }
        assertArrayEquals("SHA-256 del archivo completo", sha(parts), dl.sha256())
    }

    @Test fun smallFile() = runTest { val s = session(listOf(5_000)); val w = FakeWatch(backgroundScope, s); check(download(w), s); assertEquals(3, w.reads) }   // 2048 + 2048 + 904

    @Test fun file500kB() = runTest {
        val s = session(listOf(446_500)); val w = FakeWatch(backgroundScope, s)
        check(download(w), s)
        assertTrue("una petición por bloque de 2048 B", w.reads <= 446_500 / 2048 + 2)
    }

    @Test fun fileOver1MBInTwoSegments() = runTest { val s = session(listOf(1_048_576, 300_001)); check(download(FakeWatch(backgroundScope, s)), s) }

    @Test fun smallMtuStillCompletes() = runTest { val s = session(listOf(60_000)); check(download(FakeWatch(backgroundScope, s, att = 20)), s) }

    @Test fun repliesLostSeveralTimesAtTheSameOffset() = runTest {
        // the reported case: no fragment arrives (timeouts, 0 gaps) — 5 READ_FILE (with the client's own retries) lost at ~384 kB
        val s = session(listOf(446_500))
        val w = FakeWatch(backgroundScope, s) { i -> if (i in 192..211) Fault.DROP_ALL else Fault.OK }
        check(download(w), s)
        assertTrue(w.client.stats.timeouts >= 20)
    }

    @Test fun lostFragmentAndGattErrorsAreRetried() = runTest {
        val s = session(listOf(200_000))
        val w = FakeWatch(backgroundScope, s) { i -> when (i % 17) { 3 -> Fault.DROP_FRAGMENT; 9 -> Fault.GATT_ERROR; else -> Fault.OK } }
        check(download(w), s)
        assertTrue(w.client.stats.gaps > 0)
    }

    @Test fun delayedRepliesAreNotTakenForNewRequests() = runTest {
        val s = session(listOf(120_000))
        val w = FakeWatch(backgroundScope, s) { i -> if (i % 10 == 4) Fault.DELAY_PAST_TIMEOUT else Fault.OK }
        val dl = download(w)
        check(dl, s)                                            // no duplicated or misplaced bytes
        assertTrue("las respuestas tardías se descartan por msg_id", w.client.lateResponses > 0)
    }

    @Test fun temporaryBleLossWithReconnection() = runTest {
        val s = session(listOf(150_000)); var calls = 0
        val w = FakeWatch(backgroundScope, s)
        w.client = AvoClient(w, {})
        // the link disappears for a few attempts, then a NEW client (new connection) appears
        val dl = download(w) { calls++; if (calls in 30..33) null else w.client }
        check(dl, s)
    }

    @Test fun resumeFromIntermediateOffset() = runTest {
        val s = session(listOf(300_000))
        val dir = Files.createTempDirectory("avo_resume").toFile()
        SessionDownload(dir, "S1E8C_000009_001", 1).append(1, 0, s[0].copyOfRange(0, 131_072), s[0].size.toLong())
        val w = FakeWatch(backgroundScope, s)
        check(download(w, dir), s)
        assertTrue("no vuelve a pedir lo ya descargado", w.reads <= (300_000 - 131_072) / 2048 + 2)
    }

    @Test fun ntripActiveDuringDownload() = runTest {
        val s = session(listOf(250_000))
        val w = FakeWatch(backgroundScope, s); w.client = AvoClient(w, {})
        val rtcm = backgroundScope.launch { var seq = 0L; while (true) { w.client.writeRtcm(seq++, ByteArray(180)); delay(100) } }
        check(download(w), s)
        rtcm.cancel()
        assertTrue(w.rtcmWrites > 0)
    }

    @Test fun consecutiveDownloads() = runTest {
        repeat(3) { k -> val s = session(listOf(90_000 + k * 7_777), seed = k); check(download(FakeWatch(backgroundScope, s)), s) }
    }

    @Test fun permanentSilenceFailsWithDiagnostics() = runTest {
        val s = session(listOf(100_000))
        val w = FakeWatch(backgroundScope, s) { i -> if (i >= 10) Fault.DROP_ALL else Fault.OK }
        try { download(w); fail("debería fallar") } catch (e: ResilientDownload.Failed) {
            assertTrue(e.message!!.contains("timeouts") && e.message!!.contains("respuestas tardías"))
        }
    }
}
