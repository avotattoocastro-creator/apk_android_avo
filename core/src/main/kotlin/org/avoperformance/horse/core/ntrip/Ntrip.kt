package org.avoperformance.horse.core.ntrip

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.Base64
import java.util.Locale
import javax.net.ssl.SSLSocketFactory
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.min

enum class NtripVersion { V1, V2 }

/** The password is passed at runtime (from encrypted storage); it is never part of the source code. */
data class NtripConfig(
    val host: String,
    val port: Int = 2101,
    val mountpoint: String,
    val user: String = "",
    val password: String = "",
    val tls: Boolean = false,
    val version: NtripVersion = NtripVersion.V2,
    val sendGga: Boolean = true,
    val ggaIntervalS: Int = 10,
    val connectTimeoutMs: Int = 10_000,
    val readTimeoutMs: Int = 15_000,
    val reconnect: Boolean = true,
    val maxBackoffMs: Long = 60_000,
) {
    fun problems(): List<String> {
        val p = ArrayList<String>()
        if (host.isBlank()) p += "Falta el servidor (host)"
        if (port !in 1..65535) p += "Puerto no válido"
        if (mountpoint.isBlank()) p += "Falta el mountpoint"
        if (mountpoint.any { it.isWhitespace() || it == '/' }) p += "El mountpoint no puede contener espacios ni '/'"
        if (ggaIntervalS !in 1..600) p += "Intervalo GGA fuera de 1–600 s"
        return p
    }
}

sealed class NtripState(val texto: String) {
    object Stopped : NtripState("Detenido")
    data class Connecting(val attempt: Int) : NtripState("Conectando (intento $attempt)")
    object Streaming : NtripState("Recibiendo correcciones")
    data class WaitingRetry(val inMs: Long, val reason: String) : NtripState("Reintentando en ${inMs / 1000} s: $reason")
    data class Failed(val reason: String) : NtripState("Error: $reason")
}

data class NtripStats(
    val bytesReceived: Long = 0,
    val bytesPerSecond: Double = 0.0,
    val connectedSinceMs: Long? = null,
    val lastDataMs: Long? = null,
    val reconnects: Int = 0,
    val ggaSent: Int = 0,
    val lastError: String? = null,
)

/** Errors that will not fix themselves by retrying quickly. */
class NtripFatal(msg: String) : IOException(msg)

class SourcetableException(val mountpoints: List<String>) : IOException("Mountpoint no encontrado en el caster")

/** NMEA GGA built from the receiver position (WGS84). */
object Gga {
    /** quality: 0 invalid, 1 GPS, 2 DGPS, 4 RTK fixed, 5 RTK float. */
    fun build(utcMsOfDay: Long, lat: Double, lon: Double, quality: Int, numSv: Int, hdop: Double = 1.0, altM: Double = 0.0): String {
        val t = utcMsOfDay % 86_400_000L
        val hh = t / 3_600_000; val mm = (t / 60_000) % 60; val ss = (t % 60_000) / 1000.0
        fun dm(v: Double, degDigits: Int): String {
            val a = abs(v); val d = floor(a).toInt(); val m = (a - d) * 60.0
            return String.format(Locale.US, "%0${degDigits}d%010.7f", d, m)
        }
        val body = String.format(Locale.US, "GPGGA,%02d%02d%05.2f,%s,%s,%s,%s,%d,%02d,%.1f,%.3f,M,0.0,M,,",
            hh, mm, ss, dm(lat, 2), if (lat >= 0) "N" else "S", dm(lon, 3), if (lon >= 0) "E" else "W",
            quality, min(numSv, 99), hdop, altM)
        var cs = 0
        for (c in body) cs = cs xor c.code
        return "$" + body + "*" + String.format(Locale.US, "%02X", cs) + "\r\n"
    }

    fun quality(fixOk: Boolean, carrSoln: Int, diff: Boolean): Int = when {
        !fixOk -> 0
        carrSoln == 2 -> 4
        carrSoln == 1 -> 5
        diff -> 2
        else -> 1
    }
}

/** Position for GGA. null = no position yet (GGA is not sent). */
data class GgaPosition(val lat: Double, val lon: Double, val quality: Int, val numSv: Int, val altM: Double = 0.0)

/**
 * NTRIP v1/v2 client over a plain socket (binary-safe: after the response header
 * every byte is passed to [onData] unchanged; chunked transfer encoding is removed).
 * Blocking; run it on a dedicated thread / Dispatchers.IO.
 */
class NtripClient(
    private val cfg: NtripConfig,
    private val position: () -> GgaPosition?,
    private val onData: (ByteArray, Int, Int) -> Unit,
    private val onState: (NtripState) -> Unit,
    private val onStats: (NtripStats) -> Unit = {},
    private val clock: () -> Long = System::currentTimeMillis,
    private val sleeper: (Long) -> Unit = { Thread.sleep(it) },
) {
    @Volatile private var running = false
    @Volatile private var socket: Socket? = null
    @Volatile var stats = NtripStats(); private set

    fun stop() {
        running = false
        try { socket?.close() } catch (_: Exception) {}
    }

    fun run() {
        running = true
        var attempt = 0
        var backoff = 1000L
        while (running) {
            attempt++
            onState(NtripState.Connecting(attempt))
            try {
                session()
                backoff = 1000L
                if (!running) break
                fail("El caster cerró la conexión")
            } catch (e: SourcetableException) {
                onState(NtripState.Failed("Mountpoint \"${cfg.mountpoint}\" no existe. Disponibles: ${e.mountpoints.take(20).joinToString()}"))
                stats = stats.copy(lastError = e.message); onStats(stats)
                running = false; break
            } catch (e: NtripFatal) {
                onState(NtripState.Failed(e.message ?: "error"))
                stats = stats.copy(lastError = e.message); onStats(stats)
                running = false; break
            } catch (e: Exception) {
                if (!running) break
                fail(e.message ?: e.javaClass.simpleName)
            } finally {
                try { socket?.close() } catch (_: Exception) {}
                socket = null
                stats = stats.copy(connectedSinceMs = null); onStats(stats)
            }
            if (!running) break
            if (!cfg.reconnect) { onState(NtripState.Failed(stats.lastError ?: "desconectado")); running = false; break }
            stats = stats.copy(reconnects = stats.reconnects + 1); onStats(stats)
            onState(NtripState.WaitingRetry(backoff, stats.lastError ?: ""))
            var waited = 0L
            while (running && waited < backoff) { sleeper(200); waited += 200 }
            backoff = min(backoff * 2, cfg.maxBackoffMs)
        }
        onState(NtripState.Stopped)
    }

    private fun fail(msg: String) { stats = stats.copy(lastError = msg); onStats(stats) }

    private fun session() {
        val s: Socket = if (cfg.tls) SSLSocketFactory.getDefault().createSocket() else Socket()
        socket = s
        s.connect(InetSocketAddress(cfg.host, cfg.port), cfg.connectTimeoutMs)
        s.soTimeout = cfg.readTimeoutMs
        s.tcpNoDelay = true
        val out = s.getOutputStream()
        val ins = s.getInputStream().buffered(16 * 1024)
        out.write(request().toByteArray(Charsets.ISO_8859_1))
        out.flush()
        val status = readLine(ins) ?: throw IOException("Respuesta vacía del caster")
        val chunked: Boolean
        when {
            status.startsWith("ICY 200") -> { chunked = false; readHeaders(ins) }
            status.startsWith("SOURCETABLE 200") -> throw SourcetableException(parseSourcetable(readBody(ins)))
            status.startsWith("HTTP/1.") -> {
                val code = status.split(' ').getOrNull(1)?.toIntOrNull() ?: 0
                val h = readHeaders(ins)
                val ctype = h["content-type"] ?: ""
                when {
                    code == 401 -> throw NtripFatal("Usuario o contraseña NTRIP incorrectos (401)")
                    code == 403 -> throw NtripFatal("Acceso denegado por el caster (403)")
                    code == 404 -> throw SourcetableException(emptyList())
                    code != 200 -> throw IOException("El caster respondió $code")
                    ctype.contains("sourcetable", true) -> throw SourcetableException(parseSourcetable(readBody(ins)))
                }
                chunked = h["transfer-encoding"]?.contains("chunked", true) == true
            }
            status.contains("401") -> throw NtripFatal("Usuario o contraseña NTRIP incorrectos (401)")
            else -> throw IOException("Respuesta no reconocida: ${status.take(60)}")
        }
        val now = clock()
        stats = stats.copy(connectedSinceMs = now, lastError = null); onStats(stats)
        onState(NtripState.Streaming)
        stream(if (chunked) ChunkedInputStream(ins) else ins, out)
    }

    private fun request(): String {
        val auth = if (cfg.user.isNotEmpty()) "Authorization: Basic " +
            Base64.getEncoder().encodeToString("${cfg.user}:${cfg.password}".toByteArray(Charsets.UTF_8)) + "\r\n" else ""
        val ua = "User-Agent: NTRIP AVOPerformanceHorse/1.0\r\n"
        return when (cfg.version) {
            NtripVersion.V1 -> "GET /${cfg.mountpoint} HTTP/1.0\r\n$ua${auth}Accept: */*\r\n\r\n"
            NtripVersion.V2 -> {
                val gga = if (cfg.sendGga) position()?.let { ggaFor(it).trimEnd() } else null
                "GET /${cfg.mountpoint} HTTP/1.1\r\nHost: ${cfg.host}:${cfg.port}\r\nNtrip-Version: Ntrip/2.0\r\n$ua$auth" +
                    (if (gga != null) "Ntrip-GGA: $gga\r\n" else "") + "Connection: close\r\n\r\n"
            }
        }
    }

    private fun ggaFor(p: GgaPosition): String = Gga.build(clock() % 86_400_000L, p.lat, p.lon, p.quality, p.numSv, altM = p.altM)

    private fun stream(ins: InputStream, out: OutputStream) {
        val buf = ByteArray(4096)
        var lastGga = 0L
        var winStart = clock(); var winBytes = 0L
        while (running) {
            val now = clock()
            if (cfg.sendGga && now - lastGga >= cfg.ggaIntervalS * 1000L) {
                position()?.let { out.write(ggaFor(it).toByteArray(Charsets.US_ASCII)); out.flush(); stats = stats.copy(ggaSent = stats.ggaSent + 1) }
                lastGga = now
            }
            val n = try { ins.read(buf) } catch (e: SocketTimeoutException) {
                throw IOException("Sin datos del caster durante ${cfg.readTimeoutMs / 1000} s")
            }
            if (n < 0) return
            if (n == 0) continue
            onData(buf, 0, n)
            winBytes += n
            val t = clock()
            if (t - winStart >= 2000) {
                stats = stats.copy(bytesPerSecond = winBytes * 1000.0 / (t - winStart)); winStart = t; winBytes = 0
            }
            stats = stats.copy(bytesReceived = stats.bytesReceived + n, lastDataMs = t)
            onStats(stats)
        }
    }

    companion object {
        internal fun readLine(ins: InputStream, max: Int = 8192): String? {
            val b = ByteArrayOutputStream()
            while (b.size() < max) {
                val c = ins.read()
                if (c < 0) return if (b.size() == 0) null else b.toString("ISO-8859-1")
                if (c == '\n'.code) break
                if (c != '\r'.code) b.write(c)
            }
            return b.toString("ISO-8859-1")
        }

        internal fun readHeaders(ins: InputStream): Map<String, String> {
            val h = HashMap<String, String>()
            for (i in 0 until 100) {
                val l = readLine(ins) ?: break
                if (l.isEmpty()) break
                val k = l.indexOf(':')
                if (k > 0) h[l.substring(0, k).trim().lowercase(Locale.ROOT)] = l.substring(k + 1).trim()
            }
            return h
        }

        private fun readBody(ins: InputStream, max: Int = 512 * 1024): String {
            val b = ByteArrayOutputStream()
            val buf = ByteArray(4096)
            try {
                while (b.size() < max) { val n = ins.read(buf); if (n < 0) break; b.write(buf, 0, n); if (b.toString("ISO-8859-1").contains("ENDSOURCETABLE")) break }
            } catch (_: SocketTimeoutException) {}
            return b.toString("ISO-8859-1")
        }

        fun parseSourcetable(text: String): List<String> =
            text.lineSequence().filter { it.startsWith("STR;") }.mapNotNull { it.split(';').getOrNull(1) }.toList()

        /** Fetches the caster's mountpoint list (GET /). */
        fun fetchSourcetable(cfg: NtripConfig): List<String> {
            val s: Socket = if (cfg.tls) SSLSocketFactory.getDefault().createSocket() else Socket()
            s.use {
                it.connect(InetSocketAddress(cfg.host, cfg.port), cfg.connectTimeoutMs)
                it.soTimeout = cfg.readTimeoutMs
                val auth = if (cfg.user.isNotEmpty()) "Authorization: Basic " + Base64.getEncoder().encodeToString("${cfg.user}:${cfg.password}".toByteArray()) + "\r\n" else ""
                it.getOutputStream().write(("GET / HTTP/1.1\r\nHost: ${cfg.host}:${cfg.port}\r\nNtrip-Version: Ntrip/2.0\r\n" +
                    "User-Agent: NTRIP AVOPerformanceHorse/1.0\r\n${auth}Connection: close\r\n\r\n").toByteArray())
                val ins = it.getInputStream().buffered()
                readLine(ins)
                val h = readHeaders(ins)
                val body = if (h["transfer-encoding"]?.contains("chunked", true) == true) readBody(ChunkedInputStream(ins)) else readBody(ins)
                return parseSourcetable(body)
            }
        }
    }
}

/** HTTP/1.1 chunked transfer decoding (NTRIP v2). Binary-safe. */
class ChunkedInputStream(private val ins: InputStream) : InputStream() {
    private var left = 0
    private var eof = false

    private fun nextChunk(): Boolean {
        if (eof) return false
        var line = NtripClient.readLine(ins) ?: run { eof = true; return false }
        if (line.isEmpty()) line = NtripClient.readLine(ins) ?: run { eof = true; return false }   // CRLF after previous chunk
        val size = line.substringBefore(';').trim().toIntOrNull(16) ?: throw IOException("Cabecera de chunk inválida")
        if (size == 0) { eof = true; return false }
        left = size
        return true
    }

    override fun read(): Int {
        val b = ByteArray(1)
        val n = read(b, 0, 1)
        return if (n <= 0) -1 else b[0].toInt() and 0xFF
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (left == 0 && !nextChunk()) return -1
        val n = ins.read(b, off, min(len, left))
        if (n < 0) { eof = true; return -1 }
        left -= n
        return n
    }
}
