package org.avoperformance.horse.core

import org.avoperformance.horse.core.ntrip.Gga
import org.avoperformance.horse.core.ntrip.GgaPosition
import org.avoperformance.horse.core.ntrip.NtripClient
import org.avoperformance.horse.core.ntrip.NtripConfig
import org.avoperformance.horse.core.ntrip.NtripState
import org.avoperformance.horse.core.ntrip.NtripVersion
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.Base64
import java.util.Collections
import java.util.Random
import kotlin.concurrent.thread

/** Tests against a local fake caster (real TCP sockets on 127.0.0.1). */
class NtripTest {
    private val payload = ByteArray(200_000).also { Random(9).nextBytes(it); for (i in 0 until 2000 step 2) { it[i] = 0x0D; it[i + 1] = 0x0A } }
    private val testUser = "usuario_prueba"
    private val testPass = java.util.UUID.randomUUID().toString()   // random, only for the local fake caster

    private class Caster(val handler: (Socket, String, Map<String, String>) -> Unit) {
        val server = ServerSocket(0)
        val requests: MutableList<String> = Collections.synchronizedList(ArrayList())
        val ggaLines: MutableList<String> = Collections.synchronizedList(ArrayList())
        @Volatile var connections = 0
        val t = thread(isDaemon = true) {
            while (!server.isClosed) {
                val s = try { server.accept() } catch (e: Exception) { break }
                connections++
                thread(isDaemon = true) {
                    s.use {
                        val ins = it.getInputStream().buffered()
                        val first = NtripClient.readLine(ins) ?: return@thread
                        val h = NtripClient.readHeaders(ins)
                        requests += first
                        h["ntrip-gga"]?.let { g -> ggaLines += g }
                        thread(isDaemon = true) { try { while (true) { val l = NtripClient.readLine(ins) ?: break; if (l.startsWith("$")) ggaLines += l } } catch (_: Exception) {} }
                        handler(it, first, h)
                    }
                }
            }
        }
        val port get() = server.localPort
        fun close() = server.close()
    }

    private fun cfg(port: Int, v: NtripVersion = NtripVersion.V2, reconnect: Boolean = false) =
        NtripConfig("127.0.0.1", port, "TESTMP", testUser, testPass, version = v, ggaIntervalS = 1, readTimeoutMs = 3000, reconnect = reconnect, maxBackoffMs = 1000)

    private fun authOk(h: Map<String, String>) = h["authorization"] == "Basic " + Base64.getEncoder().encodeToString("$testUser:$testPass".toByteArray())

    private val pos = { GgaPosition(40.5, -3.25, 4, 25, 650.0) }

    private fun runClient(c: NtripConfig, stopAfterBytes: Int, states: MutableList<NtripState>, out: ByteArrayOutputStream, timeoutMs: Long = 10_000): NtripClient {
        lateinit var cl: NtripClient
        cl = NtripClient(c, pos, { b, o, n -> synchronized(out) { out.write(b, o, n) }; if (out.size() >= stopAfterBytes) cl.stop() }, { synchronized(states) { states += it } })
        val th = thread { cl.run() }
        th.join(timeoutMs)
        if (th.isAlive) { cl.stop(); th.join(2000) }
        return cl
    }

    @Test fun v2ChunkedStreamIsBinaryExact() {
        val caster = Caster { s, first, h ->
            val o = s.getOutputStream()
            if (!authOk(h) || !first.startsWith("GET /TESTMP HTTP/1.1")) { o.write("HTTP/1.1 401 Unauthorized\r\n\r\n".toByteArray()); return@Caster }
            o.write("HTTP/1.1 200 OK\r\nContent-Type: gnss/data\r\nTransfer-Encoding: chunked\r\n\r\n".toByteArray())
            var off = 0; val r = Random(1)
            while (off < payload.size) {
                val n = minOf(payload.size - off, 1 + r.nextInt(3000))
                o.write("${Integer.toHexString(n)}\r\n".toByteArray()); o.write(payload, off, n); o.write("\r\n".toByteArray()); o.flush()
                off += n
            }
            o.write("0\r\n\r\n".toByteArray()); o.flush()
            Thread.sleep(300)
        }
        val out = ByteArrayOutputStream(); val st = ArrayList<NtripState>()
        val cl = runClient(cfg(caster.port), payload.size, st, out)
        caster.close()
        assertArrayEquals(payload, out.toByteArray())
        assertTrue(st.any { it is NtripState.Streaming })
        assertEquals(payload.size.toLong(), cl.stats.bytesReceived)
        assertTrue(caster.ggaLines.isNotEmpty())
        assertTrue(caster.ggaLines[0].startsWith("\$GPGGA,"))
    }

    @Test fun v1IcyStream() {
        val caster = Caster { s, first, h ->
            val o = s.getOutputStream()
            assertTrue(first.startsWith("GET /TESTMP HTTP/1.0"))
            if (!authOk(h)) { o.write("ICY 401 Unauthorized\r\n\r\n".toByteArray()); return@Caster }
            o.write("ICY 200 OK\r\n\r\n".toByteArray()); o.write(payload); o.flush(); Thread.sleep(1500)
        }
        val out = ByteArrayOutputStream(); val st = ArrayList<NtripState>()
        runClient(cfg(caster.port, NtripVersion.V1), payload.size, st, out)
        caster.close()
        assertArrayEquals(payload, out.toByteArray())
        assertTrue("GGA must be sent in-stream for v1", caster.ggaLines.isNotEmpty())
    }

    @Test fun wrongPasswordIsFatalAndNotRetried() {
        val caster = Caster { s, _, _ -> s.getOutputStream().write("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic\r\n\r\n".toByteArray()) }
        val out = ByteArrayOutputStream(); val st = ArrayList<NtripState>()
        runClient(cfg(caster.port, reconnect = true).copy(password = "otra"), 1, st, out, 5000)
        caster.close()
        assertTrue(st.any { it is NtripState.Failed && it.reason.contains("401") })
        assertEquals(1, caster.connections)
    }

    @Test fun unknownMountpointReportsSourcetable() {
        val caster = Caster { s, _, _ ->
            s.getOutputStream().write("SOURCETABLE 200 OK\r\nContent-Type: text/plain\r\n\r\nSTR;MP_A;A;RTCM 3.3;;;;;;;;;;;;;;\r\nSTR;MP_B;B;RTCM 3.2;;;;;;;;;;;;;;\r\nENDSOURCETABLE\r\n".toByteArray())
        }
        val out = ByteArrayOutputStream(); val st = ArrayList<NtripState>()
        runClient(cfg(caster.port, reconnect = true), 1, st, out, 5000)
        caster.close()
        val f = st.filterIsInstance<NtripState.Failed>().single()
        assertTrue(f.reason.contains("MP_A") && f.reason.contains("MP_B"))
        assertEquals(1, caster.connections)
    }

    /** The caster drops the connection; the client reconnects with backoff and keeps streaming.
     *  (Corrections sent by a caster while disconnected are lost by nature; this checks the client side only.) */
    @Test fun reconnectsAfterCasterDrops() {
        val half = payload.size / 2
        var conn = 0
        val caster2 = Caster { s, _, _ ->
            val o = s.getOutputStream()
            o.write("ICY 200 OK\r\n\r\n".toByteArray())
            if (conn++ == 0) { o.write(payload, 0, half); o.flush() } else { o.write(payload, half, payload.size - half); o.flush(); Thread.sleep(1000) }
        }
        val out = ByteArrayOutputStream(); val st = ArrayList<NtripState>()
        val cl = runClient(cfg(caster2.port, NtripVersion.V1, reconnect = true), payload.size, st, out, 15_000)
        caster2.close()
        assertArrayEquals(payload, out.toByteArray())
        assertTrue(cl.stats.reconnects >= 1)
        assertTrue(st.any { it is NtripState.WaitingRetry })
    }

    @Test fun ggaChecksumAndFormat() {
        // Reference sentence checked by hand with the NMEA XOR rule
        val g = Gga.build(((12 * 3600 + 34 * 60 + 56) * 1000L + 780), 40.5, -3.25, 4, 25, 0.9, 650.0)
        assertTrue(g.startsWith("\$GPGGA,123456.78,4030.0000000,N,00315.0000000,W,4,25,0.9,650.000,M,0.0,M,,*"))
        val body = g.substring(1, g.indexOf('*'))
        var cs = 0; for (c in body) cs = cs xor c.code
        assertEquals(String.format("%02X", cs), g.substring(g.indexOf('*') + 1).trim())
        assertTrue(g.endsWith("\r\n"))
        assertEquals(4, Gga.quality(true, 2, true)); assertEquals(5, Gga.quality(true, 1, true))
        assertEquals(2, Gga.quality(true, 0, true)); assertEquals(1, Gga.quality(true, 0, false)); assertEquals(0, Gga.quality(false, 2, true))
    }

    @Test fun configValidation() {
        assertTrue(NtripConfig("", 2101, "").problems().size >= 2)
        assertTrue(NtripConfig("caster.example", 2101, "MP 1").problems().isNotEmpty())
        assertTrue(NtripConfig("caster.example", 2101, "MP1").problems().isEmpty())
    }
}
