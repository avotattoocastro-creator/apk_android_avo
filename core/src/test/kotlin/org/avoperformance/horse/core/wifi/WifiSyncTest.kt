package org.avoperformance.horse.core.wifi

import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.avoperformance.horse.core.bytes.ByteWriter
import org.avoperformance.horse.core.sync.SessionDownload
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import kotlin.random.Random

/** Simulated watch: CHEST V3.7.4 HTTP semantics (Range, If-Match/etag, token, recording, SHA over segments). */
class FakeWatch {
    val sessions = LinkedHashMap<String, MutableList<ByteArray>>()
    val open = HashSet<String>()
    var token = "a".repeat(32)
    var recording = false
    var sd = true
    var batteryPct = 80
    var bleUp = true
    var wifiSupported = true
    var apOn = false
    var starts = 0; var stops = 0
    var bytesServed = 0L
    /** Cuts the connection after serving this many bytes (once). */
    var cutAfter: Long = -1
    /** Modifies the file after serving this many bytes (once). */
    var modifyAfter: Long = -1
    var wrongSha = false
    var connectFails = false
    val completes = ArrayList<String>()

    fun etag(id: String): String {
        var h = 2166136261u
        sessions[id]!!.forEachIndexed { i, s -> h = (h xor s.size.toUInt()) * 16777619u; h = (h xor (i + 1).toUInt()) * 16777619u; h = (h xor s.contentHashCode().toUInt()) * 16777619u }
        return "%08x".format(h.toInt())
    }
    fun sha(id: String): String { val md = MessageDigest.getInstance("SHA-256"); sessions[id]!!.forEach { md.update(it) }; return md.digest().joinToString("") { "%02x".format(it) } }

    fun http(tok: String) = object : WatchHttp {
        private fun guard() {
            if (!apOn) throw IOException("red del reloj no disponible")
            if (tok != token) throw AuthException()
            if (recording) throw RecordingException()
        }
        override fun list() = run { guard(); sessions.map { (id, s) -> RemoteTraining(id, id !in open, s.size, s.sumOf { it.size.toLong() }, 1L, 1L, etag(id)) } }
        override fun metadata(id: String) = run { guard(); val s = sessions[id] ?: throw WatchHttpException(404, "id"); RemoteMeta(id, id !in open, 1, s.sumOf { it.size.toLong() }, etag(id), s.map { it.size.toLong() }) }
        override fun sha256(id: String) = run { guard(); if (wrongSha) "0".repeat(64) else sha(id) }
        override fun openSegment(id: String, seg: Int, from: Long, etag: String): InputStream {
            guard()
            if (etag != etag(id)) throw ChangedException()
            val data = sessions[id]!![seg - 1]
            val src = ByteArrayInputStream(data, from.toInt(), data.size - from.toInt())
            return object : InputStream() {
                override fun read(): Int { val b = ByteArray(1); return if (read(b, 0, 1) < 0) -1 else b[0].toInt() and 0xFF }
                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    if (!apOn) throw IOException("Wi-Fi caído")
                    if (cutAfter in 0..bytesServed) { cutAfter = -1; apOn = false; throw IOException("Wi-Fi caído") }
                    if (modifyAfter in 0..bytesServed) { modifyAfter = -1; sessions[id]!![seg - 1] = data.copyOf().also { it[0] = (it[0] + 1).toByte() } }
                    val n = src.read(b, off, minOf(len, 8192))
                    if (n > 0) bytesServed += n
                    return n
                }
            }
        }
        override fun complete(id: String, sha256: String, done: Boolean) { guard(); completes += "$id:$done"; if (done) apOn = false }
    }

    val control = object : WatchWifiControl {
        override suspend fun start(): WatchWifiControl.Start {
            if (!bleUp) throw IOException("BLE desconectado")
            if (!wifiSupported) return WatchWifiControl.Start.Unsupported
            if (recording) return WatchWifiControl.Start.Refused("grabando", true)
            if (!sd) return WatchWifiControl.Start.Refused("sin microSD", true)
            if (batteryPct < 15) return WatchWifiControl.Start.Refused("batería baja", true)
            starts++; apOn = true
            return WatchWifiControl.Start.Ok(WifiCredentials("AVO_CHEST_ABCD", "pw-123456789", token, "192.168.4.1", ByteArray(6), 1, 80, 45))
        }
        override suspend fun stop() { stops++; apOn = false }
        override fun recording() = recording
    }

    val connector = object : WifiConnector {
        override suspend fun connect(creds: WifiCredentials): WifiConnector.Link? =
            if (connectFails || !apOn) null else object : WifiConnector.Link { override val http = http(creds.token); override fun close() {} }
    }
}

class WifiSyncTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var w: FakeWatch
    private val saved = LinkedHashMap<String, String>()
    private fun dirFor(id: String) = File(tmp.root, id)
    private fun coordinator() = WifiSyncCoordinator(w.control, w.connector, ::dirFor, { id, _, sha, _ -> saved[id] = sha })

    private fun session(id: String, vararg sizes: Int, seed: Int = id.hashCode()) {
        val r = Random(seed)
        w.sessions[id] = sizes.map { r.nextBytes(it) }.toMutableList()
    }

    @Before fun setUp() { w = FakeWatch(); saved.clear() }

    @Test fun t01_smallFile() = runBlocking {
        session("S0001", 3_700)
        val rep = coordinator().sync(listOf("S0001" to null))
        assertEquals(listOf("S0001"), rep.verified)
        assertEquals(w.sha("S0001"), saved["S0001"])
        assertEquals(1, w.starts); assertEquals(1, w.stops)       // Wi-Fi off at the end
    }

    @Test fun t02_severalMegabytesInSegments() = runBlocking {
        session("S0002", 2_000_000, 2_000_000, 1_300_000)
        val rep = coordinator().sync(listOf("S0002" to null))
        assertEquals(listOf("S0002"), rep.verified)
        assertEquals(5_300_000L, WifiDownloader.segFiles(dirFor("S0002")).sumOf { it.length() })
        assertEquals(3, WifiDownloader.segFiles(dirFor("S0002")).size)
    }

    @Test fun t03_t04_t05_wifiCutThenReconnectResumesFromValidBlock() = runBlocking {
        session("S0003", 600_000, 400_000)
        w.cutAfter = 450_000
        val c = coordinator()
        val r1 = c.sync(listOf("S0003" to null))
        assertTrue(r1.verified.isEmpty())
        assertEquals(1, w.stops)                                  // turned off even with an error
        val partial = WifiDownloader.segFiles(dirFor("S0003")).sumOf { it.length() }
        assertTrue(partial in 400_000..460_000)                   // the valid progress is kept
        w.bytesServed = 0
        val r2 = c.sync(listOf("S0003" to null))
        assertEquals(listOf("S0003"), r2.verified)
        assertEquals(1_000_000L - partial, w.bytesServed)         // only the missing part is downloaded
    }

    @Test fun t06_fileModifiedDuringDownloadIsDiscardedAndRepeated() = runBlocking {
        session("S0006", 300_000, 300_000)
        w.modifyAfter = 100_000
        val c = coordinator()
        val r1 = c.sync(listOf("S0006" to null))
        assertFalse("must not verify mixed data", "S0006" in r1.verified)
        val r2 = c.sync(listOf("S0006" to null))
        assertEquals(listOf("S0006"), r2.verified)
        assertEquals(w.sha("S0006"), saved["S0006"])              // final content = current watch content
    }

    @Test fun t07_wrongSha256NeverSavesAsVerified() = runBlocking {
        session("S0007", 50_000)
        w.wrongSha = true
        val rep = coordinator().sync(listOf("S0007" to null))
        assertTrue(rep.verified.isEmpty())
        assertEquals("Huella SHA-256 distinta", rep.failed["S0007"])
        assertTrue(saved.isEmpty())
        assertTrue(WifiDownloader.segFiles(dirFor("S0007")).isEmpty())   // nothing unverified is left
    }

    @Test fun t08_duplicateAlreadyVerifiedIsNotDownloadedAgain() = runBlocking {
        session("S0008", 80_000)
        val c = coordinator()
        c.sync(listOf("S0008" to null))
        w.bytesServed = 0
        val rep = c.sync(listOf("S0008" to saved["S0008"]))
        assertEquals(listOf("S0008"), rep.verified)
        assertEquals(0L, w.bytesServed)
    }

    @Test fun t09_noMicroSd() = runBlocking {
        session("S0009", 1000); w.sd = false
        val rep = coordinator().sync(listOf("S0009" to null))
        assertTrue(rep.verified.isEmpty() && rep.fallbackBle.isEmpty())
        assertEquals("sin microSD", rep.failed["S0009"])
        assertEquals(0, w.starts)
    }

    @Test fun t10_bleDisconnected() = runBlocking {
        session("S0010", 1000); w.bleUp = false
        val c = coordinator()
        val rep = c.sync(listOf("S0010" to null))
        assertTrue(rep.verified.isEmpty())
        assertEquals(0, w.starts)
        assertEquals(WifiSyncState.WAITING, c.progress.value.state)
    }

    @Test fun t11_lowBattery() = runBlocking {
        session("S0011", 1000); w.batteryPct = 10
        val rep = coordinator().sync(listOf("S0011" to null))
        assertEquals("batería baja", rep.failed["S0011"]); assertEquals(0, w.starts)
    }

    @Test fun t12_activeRecordingNeverStartsWifi() = runBlocking {
        session("S0012", 1000); w.recording = true
        val rep = coordinator().sync(listOf("S0012" to null))
        assertTrue(rep.verified.isEmpty()); assertEquals(0, w.starts)
    }

    @Test fun t12b_recordingStartsDuringDownloadStopsTransfer() = runBlocking {
        session("S012B", 500_000)
        val origConnector = w.connector
        val conn = object : WifiConnector {
            override suspend fun connect(creds: WifiCredentials) = origConnector.connect(creds)?.let { l ->
                object : WifiConnector.Link {
                    override val http = object : WatchHttp by l.http {
                        override fun openSegment(id: String, seg: Int, from: Long, etag: String): InputStream {
                            val ins = l.http.openSegment(id, seg, from, etag)
                            return object : InputStream() {
                                var n = 0
                                override fun read() = ins.read()
                                override fun read(b: ByteArray, off: Int, len: Int): Int { if (n > 100_000) w.recording = true; return ins.read(b, off, len).also { n += maxOf(it, 0) } }
                            }
                        }
                    }
                    override fun close() = l.close()
                }
            }
        }
        val rep = WifiSyncCoordinator(w.control, conn, ::dirFor, { id, _, sha, _ -> saved[id] = sha }).sync(listOf("S012B" to null))
        assertTrue(rep.verified.isEmpty())
        assertEquals("grabando", rep.failed["S012B"])
        assertEquals(1, w.stops)
        assertTrue(saved.isEmpty())
    }

    @Test fun t13_severalPendingWithOneWifiActivation() = runBlocking {
        session("S1301", 10_000); session("S1302", 200_000, 50_000); session("S1303", 70_000)
        val rep = coordinator().sync(listOf("S1301" to null, "S1302" to null, "S1303" to null))
        assertEquals(listOf("S1301", "S1302", "S1303"), rep.verified)
        assertEquals(1, w.starts); assertEquals(1, w.stops)
        assertTrue(w.completes.last().endsWith(":true"))          // final confirmation → watch turns Wi-Fi off
    }

    @Test fun t14_manualCancellation() = runBlocking {
        session("S0014", 1_000_000)
        lateinit var c: WifiSyncCoordinator
        val conn = object : WifiConnector {
            override suspend fun connect(creds: WifiCredentials) = w.connector.connect(creds)?.also { c.cancel() }   // the user cancels while connecting
        }
        c = WifiSyncCoordinator(w.control, conn, ::dirFor, { id, _, sha, _ -> saved[id] = sha })
        val rep = c.sync(listOf("S0014" to null))
        assertFalse("S0014" in rep.verified)
        assertTrue(saved.isEmpty())
        assertEquals(WifiSyncState.CANCELLED, c.progress.value.state)
        assertEquals(1, w.starts); assertEquals(1, w.stops)       // Wi-Fi always off
    }

    @Test fun t15_noInternetIsIrrelevantForTheWatchNetwork() = runBlocking {
        // the watch network has no Internet; the connection is requested without NET_CAPABILITY_INTERNET
        session("S0015", 5_000)
        assertEquals(listOf("S0015"), coordinator().sync(listOf("S0015" to null)).verified)
    }

    @Test fun t16_androidRejectsOrChangesNetworkFallsBackToBle() = runBlocking {
        session("S0016", 5_000); w.connectFails = true
        val rep = coordinator().sync(listOf("S0016" to null))
        assertEquals(listOf("S0016"), rep.fallbackBle)
        assertEquals(1, w.stops)
    }

    @Test fun t16b_firmwareWithoutWifiFallsBackToBleByCapability() = runBlocking {
        session("S016B", 5_000); w.wifiSupported = false
        assertEquals(listOf("S016B"), coordinator().sync(listOf("S016B" to null)).fallbackBle)
    }

    @Test fun t17_t19_watchRebootInvalidatesToken() = runBlocking {
        session("S0017", 300_000)
        val c = coordinator()
        val conn = object : WifiConnector {
            override suspend fun connect(creds: WifiCredentials) = w.connector.connect(creds.copy(token = "b".repeat(32)))
        }
        val r1 = WifiSyncCoordinator(w.control, conn, ::dirFor, { _, _, _, _ -> }).sync(listOf("S0017" to null))
        assertEquals("Token rechazado por el reloj", r1.failed["S0017"])
        w.token = "c".repeat(32)                                  // reboot: new token on the next start
        assertEquals(listOf("S0017"), c.sync(listOf("S0017" to null)).verified)
    }

    @Test fun t18_appRestartResumesFromDisk() = runBlocking {
        session("S0018", 500_000)
        w.cutAfter = 200_000
        coordinator().sync(listOf("S0018" to null))
        w.bytesServed = 0
        val fresh = WifiSyncCoordinator(w.control, w.connector, ::dirFor, { id, _, sha, _ -> saved[id] = sha })   // new instance = app restarted
        assertEquals(listOf("S0018"), fresh.sync(listOf("S0018" to null)).verified)
        assertTrue(w.bytesServed in 290_000..310_000)
    }

    @Test fun t20_twoSimultaneousSyncsOnlyOneRuns() = runBlocking {
        session("S0020", 200_000)
        val slow = object : WifiConnector {
            override suspend fun connect(creds: WifiCredentials) = run { kotlinx.coroutines.delay(100); w.connector.connect(creds) }
        }
        val c = WifiSyncCoordinator(w.control, slow, ::dirFor, { id, _, sha, _ -> saved[id] = sha })
        val a = async { c.sync(listOf("S0020" to null)) }
        val b = async { c.sync(listOf("S0020" to null)) }
        val ra = a.await(); val rb = b.await()
        assertFalse(ra.skipped); assertTrue(rb.skipped)
        assertEquals(1, w.starts); assertEquals(1, w.stops)
    }

    @Test fun rawCompatibility_bleAndWifiProduceSameFilesAndHash() = runBlocking {
        session("S0099", 120_000, 40_000)
        coordinator().sync(listOf("S0099" to null))
        val dl = SessionDownload(dirFor("S0099"), "S0099", 2)
        assertEquals(WifiDownloader.sha256(dirFor("S0099")), dl.sha256().joinToString("") { "%02x".format(it) })
        assertEquals(160_000L, dl.downloadedBytes())
        assertEquals(listOf("P001.avr", "P002.avr"), dl.segments().map { it.name })
    }

    @Test fun bleCanContinueAWifiPartialDownload() = runBlocking {
        session("S0098", 100_000)
        w.cutAfter = 30_000
        coordinator().sync(listOf("S0098" to null))
        val pos = SessionDownload(dirFor("S0098"), "S0098", 1).position()
        assertEquals(1, pos.first)
        assertTrue(pos.second in 24_000..40_000)                  // BLE resumes from the same byte
    }

    @Test fun credentialsDecodeAndNoSecretsInToString() {
        val b = ByteWriter().u8(1).str("AVO_CHEST_1A2B", 33).str("Secreto12345678", 33).str("f".repeat(32), 33).str("192.168.4.1", 16)
            .bytes(byteArrayOf(1, 2, 3, 4, 5, 6)).u8(1).u16(80).u16(45).toByteArray()
        val c = WifiCredentials.decode(b)!!
        assertEquals("AVO_CHEST_1A2B", c.ssid); assertEquals(80, c.port); assertEquals("01:02:03:04:05:06", c.bssidText)
        assertFalse(c.toString().contains("Secreto")); assertFalse(c.toString().contains("fff"))
        assertNull(WifiCredentials.decode(byteArrayOf(2)))
    }

    @Test fun jsonParsing() {
        val l = WatchHttp.parseList("""{"trainings":[{"id":"S1E8C_000150_001","state":2,"ready":true,"segments":2,"size":3700,"start_rtc_ms":1792368000000,"active_ms":4000,"etag":"0a0b0c0d"}]}""")
        assertEquals("S1E8C_000150_001", l.single().id); assertEquals(1792368000000L, l.single().startRtcMs)
        val m = WatchHttp.parseMeta("""{"id":"S1","state":2,"ready":true,"raw_format":3,"size":30,"etag":"ab","segments":[10,20]}""")
        assertEquals(listOf(10L, 20L), m.segmentSizes)
        assertEquals("ab".repeat(32), WatchHttp.parseSha("""{"sha256":"${"AB".repeat(32)}"}"""))
    }
}
