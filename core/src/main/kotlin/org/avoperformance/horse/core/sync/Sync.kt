package org.avoperformance.horse.core.sync

import org.avoperformance.horse.core.ble.WatchFileState
import org.avoperformance.horse.core.ble.WatchSessionEntry
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * State of one watch training on the phone. Order matters: a file only moves forward,
 * and VERIFICADO_SERVIDOR is reachable only with a real server confirmation.
 */
enum class SyncState(val texto: String) {
    EN_RELOJ("Solo en el reloj"),
    GRABANDO("Grabando en el reloj"),
    DESCARGANDO("Descargando"),
    DESCARGADO("Descargado, pendiente de verificar"),
    VERIFICADO_LOCAL("Descargado y verificado con el reloj (SHA-256)"),
    ERROR_INTEGRIDAD("La huella no coincide con la del reloj"),
    PENDIENTE_SERVIDOR("Pendiente de subir (servidor no configurado)"),
    SUBIENDO("Subiendo al servidor"),
    VERIFICADO_SERVIDOR("Verificado por el servidor"),
    MARCADO_EN_RELOJ("Verificado y marcado como subido en el reloj"),
}

data class LocalTraining(
    val sessionId: String,
    val segments: Int,
    val totalBytes: Long,
    val downloadedBytes: Long,
    val localSha256Hex: String?,
    val watchSha256Hex: String?,
    val serverSha256Hex: String?,
    val state: SyncState,
    val watchState: WatchFileState,
    val startRtcMs: Long,
    val activeMs: Long,
)

object SyncRules {
    /** Merge the watch list with what the phone already has. Never creates duplicates: key = sessionId. */
    fun merge(watch: List<WatchSessionEntry>, local: Map<String, LocalTraining>): List<LocalTraining> {
        val out = LinkedHashMap<String, LocalTraining>()
        for (e in watch) {
            val l = local[e.sessionId]
            val st = when {
                e.recordingNow -> SyncState.GRABANDO
                l == null -> if (e.state == WatchFileState.UPLOADED) SyncState.MARCADO_EN_RELOJ else SyncState.EN_RELOJ
                l.state == SyncState.GRABANDO -> SyncState.EN_RELOJ
                // The session grew after a partial download (resumed after reboot): re-verify
                l.totalBytes != e.totalBytes && l.state.ordinal >= SyncState.DESCARGADO.ordinal && l.state != SyncState.MARCADO_EN_RELOJ && l.state != SyncState.VERIFICADO_SERVIDOR -> SyncState.DESCARGANDO
                else -> l.state
            }
            out[e.sessionId] = (l ?: LocalTraining(e.sessionId, e.segments, e.totalBytes, 0, null, null, null, st, e.state, e.startRtcMs, e.activeMs))
                .copy(segments = e.segments, totalBytes = e.totalBytes, state = st, watchState = e.state, startRtcMs = e.startRtcMs, activeMs = e.activeMs)
        }
        for ((id, l) in local) if (id !in out) out[id] = l   // downloaded and later deleted on the watch: kept on the phone
        return out.values.toList()
    }

    fun canDownload(e: WatchSessionEntry) = !e.recordingNow && e.state != WatchFileState.OPEN

    /** MARK_UPLOADED is only allowed with a server-confirmed hash equal to the local one. */
    fun canMarkUploaded(t: LocalTraining) = t.state == SyncState.VERIFICADO_SERVIDOR &&
        t.serverSha256Hex != null && t.serverSha256Hex == t.localSha256Hex && t.localSha256Hex == t.watchSha256Hex

    /** The app never deletes from the watch on its own. Deletion is a manual action and only for verified uploads. */
    fun canOfferDelete(t: LocalTraining) = t.state == SyncState.MARCADO_EN_RELOJ
}

/**
 * Resumable download of a session (all segments) into a local directory:
 * <dir>/P001.avr, P002.avr, … (same names as on the watch).
 * Progress = size of the local files; restarting continues where it stopped.
 */
class SessionDownload(private val dir: File, val sessionId: String, private val segmentsHint: Int) {
    init { dir.mkdirs() }

    fun segFile(seg: Int) = File(dir, String.format("P%03d.avr", seg))

    /** Next request (segment, offset). Segment index starts at 1. */
    fun position(): Pair<Int, Long> {
        var seg = 1
        while (seg < segmentsHint && segFile(seg + 1).exists()) seg++
        return seg to (if (segFile(seg).exists()) segFile(seg).length() else 0L)
    }

    /**
     * Appends a verified chunk. [fileSize] is the watch size of this segment.
     * Returns the next (segment, offset) or null when finished.
     */
    fun append(segment: Int, offset: Long, data: ByteArray, fileSize: Long): Pair<Int, Long>? {
        val f = segFile(segment)
        RandomAccessFile(f, "rw").use { raf ->
            require(raf.length() == offset) { "offset ${offset} != local ${raf.length()}" }
            raf.seek(offset); raf.write(data)
            raf.fd.sync()
        }
        val end = offset + data.size
        return when {
            end < fileSize -> segment to end
            segment < segmentsHint -> (segment + 1) to 0L
            else -> null
        }
    }

    /** Called when the watch answers NOT_FOUND for a segment: there are no more segments. */
    fun downloadedBytes(): Long = (1..maxOf(segmentsHint, 1)).sumOf { if (segFile(it).exists()) segFile(it).length() else 0L }

    /** SHA-256 over the concatenated segments, in the same order the watch hashes them. */
    fun sha256(): ByteArray {
        val md = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(64 * 1024)
        var seg = 1
        while (segFile(seg).exists()) {
            segFile(seg).inputStream().use { ins -> while (true) { val n = ins.read(buf); if (n < 0) break; md.update(buf, 0, n) } }
            seg++
        }
        return md.digest()
    }

    fun segments(): List<File> { val l = ArrayList<File>(); var s = 1; while (segFile(s).exists()) { l += segFile(s); s++ }; return l }
}
