package org.avoperformance.horse.core.wifi

import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.engine.J
import org.avoperformance.horse.core.engine.MiniJson
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

/*
 * Training download over Wi-Fi (watch CHEST V3.7.4+). Pure logic, no Android: the app supplies the HTTP
 * transport bound to the watch network. Protocol: firmware/chest/V3_7_4_WIFI/PROTOCOLO_WIFI.md.
 *
 * Writes the segments to the same files as the BLE download (P001.avr, P002.avr…), so a download
 * interrupted on one transport continues on the other from the last confirmed byte.
 */

/** Credentials that the watch returns to WIFI_SYNC(start) over authenticated BLE. Never stored on disk. */
data class WifiCredentials(
    val ssid: String, val password: String, val token: String, val ip: String,
    val bssid: ByteArray, val channel: Int, val port: Int, val idleTimeoutS: Int,
) {
    val bssidText: String get() = bssid.joinToString(":") { "%02x".format(it) }
    override fun toString() = "WifiCredentials($ssid, ch$channel, $ip:$port)"   // never the password or the token

    companion object {
        fun decode(p: ByteArray): WifiCredentials? {
            val r = ByteReader(p)
            if (r.u8() != 1) return null
            val ssid = r.str(33); val pw = r.str(33); val tok = r.str(33); val ip = r.str(16)
            val bssid = r.bytes(6); val ch = r.u8(); val port = r.u16(); val idle = r.u16()
            if (!r.ok || !ssid.startsWith("AVO_CHEST_") || pw.length < 8 || tok.length != 32 || ip.isBlank()) return null
            return WifiCredentials(ssid, pw, tok, ip, bssid, ch, port, idle)
        }
    }
}

data class RemoteTraining(val id: String, val ready: Boolean, val segments: Int, val size: Long, val startRtcMs: Long, val activeMs: Long, val etag: String)
data class RemoteMeta(val id: String, val ready: Boolean, val rawFormat: Int, val size: Long, val etag: String, val segmentSizes: List<Long>)

/** HTTP errors with meaning for the logic. */
open class WatchHttpException(val code: Int, msg: String) : IOException(msg)
class AuthException : WatchHttpException(401, "Token rechazado por el reloj")
class RecordingException : WatchHttpException(409, "El reloj está grabando")
class ChangedException : WatchHttpException(412, "El fichero cambió en el reloj")

/** Watch HTTP API (implemented by the app with HttpURLConnection on the watch Network; fake in tests). */
interface WatchHttp {
    fun list(): List<RemoteTraining>
    fun metadata(id: String): RemoteMeta
    fun sha256(id: String): String
    /** Opens segment [seg] from [from] (Range). [etag] → If-Match: if it changed, ChangedException. */
    fun openSegment(id: String, seg: Int, from: Long, etag: String): InputStream
    fun complete(id: String, sha256: String, done: Boolean)

    companion object {
        fun parseList(json: String): List<RemoteTraining> = J(MiniJson.parse(json))["trainings"].let { arr ->
            (arr.v as? List<*>)?.indices?.map { i ->
                val o = arr[i]
                RemoteTraining(o["id"].s(), o["ready"].b(), o["segments"].i(), o["size"].l() ?: 0, o["start_rtc_ms"].l() ?: 0, o["active_ms"].l() ?: 0, o["etag"].s())
            }.orEmpty()
        }
        fun parseMeta(json: String): RemoteMeta = J(MiniJson.parse(json)).let { o ->
            val segs = o["segments"].let { a -> (a.v as? List<*>)?.indices?.map { a[it].l() ?: 0L }.orEmpty() }
            RemoteMeta(o["id"].s(), o["ready"].b(), o["raw_format"].i(), o["size"].l() ?: 0, o["etag"].s(), segs)
        }
        fun parseSha(json: String): String = J(MiniJson.parse(json))["sha256"].s().lowercase()
    }
}

/** States of the synchronization (a single owner: AvoWifiSyncManager). */
enum class WifiSyncState(val texto: String) {
    IDLE(""), DISCOVERING("Buscando entrenamientos…"), WIFI_STARTING("Conectando con el reloj…"),
    CONNECTING("Conectando con el reloj…"), DOWNLOADING("Descargando"), VERIFYING("Verificando…"),
    COMPLETED("Entrenamiento guardado ✓"), CLEANUP(""), PAUSED("En pausa"),
    WAITING("Pendiente de conexión"), CANCELLED("Cancelado"), ERROR("Error"),
}

/** Result per training. */
sealed interface DownloadResult {
    data class Verified(val sha256: String, val bytes: Long) : DownloadResult
    data object AlreadyLocal : DownloadResult
    data object NotReady : DownloadResult
    data class Mismatch(val local: String, val remote: String) : DownloadResult
    data object Cancelled : DownloadResult
}

/**
 * Resumable download of a training. Never loads whole files into memory: copies in 64 KB blocks
 * and only counts bytes already written (the progress is real). Before reusing local data it checks the
 * file version (etag): if the watch file changed, it discards the partial copy.
 */
class WifiDownloader(
    private val http: WatchHttp,
    private val dirFor: (String) -> File,
    private val cancelled: () -> Boolean = { false },
) {
    /** [onProgress] (confirmed bytes, total). */
    fun download(id: String, knownLocalSha: String? = null, onProgress: (Long, Long) -> Unit = { _, _ -> }): DownloadResult {
        val meta = http.metadata(id)
        if (!meta.ready) return DownloadResult.NotReady
        val dir = dirFor(id).also { it.mkdirs() }
        val etagFile = File(dir, ".wifi_etag")
        // Different version from the one partially downloaded → start again (do not mix data from two files)
        val prevEtag = etagFile.takeIf { it.exists() }?.readText()?.trim()
        if (prevEtag != null && prevEtag != meta.etag) segFiles(dir).forEach { it.delete() }
        // A local segment bigger than the remote one or the wrong number of segments → inconsistent, discarded
        segFiles(dir).forEach { f ->
            val n = f.name.substring(1, 4).toIntOrNull() ?: 0
            if (n < 1 || n > meta.segmentSizes.size || f.length() > meta.segmentSizes[n - 1]) f.delete()
        }
        etagFile.writeText(meta.etag)
        val total = meta.segmentSizes.sum()
        // Already complete and verified locally with the same content: nothing to download (duplicate)
        if (knownLocalSha != null && localBytes(dir, meta) == total && sha256(dir) == knownLocalSha.lowercase()) return DownloadResult.AlreadyLocal
        var confirmed = localBytes(dir, meta)
        onProgress(confirmed, total)
        val buf = ByteArray(64 * 1024)
        for ((i, size) in meta.segmentSizes.withIndex()) {
            val seg = i + 1
            val f = segFile(dir, seg)
            var have = if (f.exists()) f.length() else 0L
            if (have >= size) continue
            if (cancelled()) return DownloadResult.Cancelled
            try {
                http.openSegment(id, seg, have, meta.etag).use { ins ->
                    RandomAccessFile(f, "rw").use { raf ->
                        raf.seek(have)
                        while (have < size) {
                            if (cancelled()) { raf.fd.sync(); return DownloadResult.Cancelled }
                            val n = ins.read(buf, 0, minOf(buf.size.toLong(), size - have).toInt())
                            if (n < 0) break
                            raf.write(buf, 0, n)
                            have += n; confirmed += n
                            onProgress(confirmed, total)
                        }
                        raf.fd.sync()   // what is counted is on disk
                    }
                }
            } catch (e: ChangedException) {
                segFiles(dir).forEach { it.delete() }; etagFile.delete()
                throw e
            }
            if (have < size) throw IOException("Conexión cortada en el segmento $seg ($have de $size B)")
        }
        val local = sha256(dir)
        val remote = http.sha256(id)
        if (local != remote) {
            segFiles(dir).forEach { it.delete() }; etagFile.delete()
            return DownloadResult.Mismatch(local, remote)
        }
        etagFile.delete()
        return DownloadResult.Verified(local, total)
    }

    companion object {
        fun segFile(dir: File, seg: Int) = File(dir, String.format("P%03d.avr", seg))
        fun segFiles(dir: File): List<File> = dir.listFiles { f -> f.name.matches(Regex("P\\d{3}\\.avr")) }?.sortedBy { it.name }.orEmpty()
        private fun localBytes(dir: File, m: RemoteMeta) = m.segmentSizes.indices.sumOf { val f = segFile(dir, it + 1); if (f.exists()) minOf(f.length(), m.segmentSizes[it]) else 0L }
        /** Same calculation as the watch: SHA-256 of the concatenated segments in order. */
        fun sha256(dir: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(64 * 1024)
            var s = 1
            while (true) {
                val f = segFile(dir, s)
                if (!f.exists()) break
                f.inputStream().use { ins -> while (true) { val n = ins.read(buf); if (n < 0) break; md.update(buf, 0, n) } }
                s++
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
