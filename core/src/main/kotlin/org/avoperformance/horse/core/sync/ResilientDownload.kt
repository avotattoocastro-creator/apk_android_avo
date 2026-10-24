package org.avoperformance.horse.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.avoperformance.horse.core.ble.AvoClient
import org.avoperformance.horse.core.ble.BleRequestException
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.FileChunk

/**
 * Resumable, verifiable download of one watch session over READ_FILE.
 * - Chunks of [CHUNK] bytes (the firmware answers at most 2048 B per READ_FILE since V3.5.4).
 * - The local file only grows by verified chunks (CRC-32 + exact offset); [SessionDownload.append] rejects
 *   any chunk whose offset is not the current local length, so nothing is written twice or out of order.
 * - Transient failures (no answer, busy, bad CRC, unexpected offset from a stale answer, GATT/IO errors, link
 *   lost) retry the SAME offset with growing pauses; the link may be replaced (client is re-read every attempt).
 * - Resumes from whatever is already on disk.
 */
class ResilientDownload(
    private val client: () -> AvoClient?,
    private val maxFailures: Int = 8,
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {
    companion object { const val CHUNK = 2048 }

    class Failed(message: String) : Exception(message)

    var retries = 0; private set

    suspend fun run(sessionId: String, dl: SessionDownload, isBlocked: () -> String? = { null }, progress: suspend (Long, String) -> Unit = { _, _ -> }): Long {
        var pos: Pair<Int, Long>? = dl.position()
        while (pos != null) {
            val chunk = readChunk(sessionId, pos.first, pos.second, dl.downloadedBytes(), isBlocked, progress) ?: break
            pos = dl.append(pos.first, pos.second, chunk.data, chunk.fileSize)
            progress(dl.downloadedBytes(), "Descargando")
        }
        return dl.downloadedBytes()
    }

    private suspend fun readChunk(sessionId: String, segment: Int, offset: Long, got: Long, isBlocked: () -> String?, progress: suspend (Long, String) -> Unit): FileChunk? {
        var failures = 0
        while (true) {
            isBlocked()?.let { throw Failed(it) }
            val c = client()
            if (c == null) {
                if (++failures > maxFailures) throw Failed("Conexión con el reloj perdida en ${got / 1024} kB")
                retries++
                progress(got, "Esperando reconexión con el reloj…")
                pause(3000); continue
            }
            try {
                return c.readChunk(sessionId, segment, offset, CHUNK)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val transient = (e is BleRequestException && e.status in setOf(BleStatus.TIMEOUT, BleStatus.BUSY, BleStatus.BAD_CRC, BleStatus.BAD_FORMAT)) || e is java.io.IOException
                if (!transient) throw e
                failures++; retries++
                val st = c.stats
                if (failures > maxFailures)
                    throw Failed("${e.message} en ${got / 1024} kB tras $failures intentos (timeouts ${st.timeouts}, fragmentos perdidos ${st.gaps}, CRC ${st.crcErrors}, respuestas tardías ${c.lateResponses})")
                progress(got, "Reintentando bloque ($failures/$maxFailures)…")
                pause(minOf(8000L, 1000L shl (failures - 1)))
            }
        }
    }
}
