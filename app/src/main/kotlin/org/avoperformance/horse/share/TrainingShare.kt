package org.avoperformance.horse.share

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.avoperformance.horse.data.TrainingEntity
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Export a portable archive using Android's sharesheet; WhatsApp transport never needs our server. */
object TrainingShare {
    suspend fun prepare(context: Context, t: TrainingEntity, horseName: String, riderName: String): Intent = withContext(Dispatchers.IO) {
        val directory = t.localDir?.let(::File) ?: error("Entrenamiento no descargado")
        val files = directory.listFiles()?.filter { it.isFile }?.sortedBy { it.name } ?: emptyList()
        require(files.isNotEmpty()) { "No hay segmentos locales" }
        require(t.localSha256 != null && t.watchSha256 != null && t.localSha256.equals(t.watchSha256, true)) {
            "Es necesario verificar la descarga con el reloj antes de compartir"
        }
        require(horseName.isNotBlank() && riderName.isNotBlank()) {
            "Selecciona el caballo y el jinete antes de compartir"
        }
        val share = File(context.cacheDir, "share").also { it.mkdirs() }
        val target = File(share, "AVO_${t.sessionId.replace(Regex("[^A-Za-z0-9_-]"), "_")}.avo")
        ZipOutputStream(target.outputStream().buffered()).use { zip ->
            val manifest = org.json.JSONObject().put("format", "AVO-TRAINING-1")
                .put("sessionId", t.sessionId).put("horseCode", t.horseCode ?: "").put("riderCode", t.riderCode ?: "")
                .put("horseName", horseName).put("riderName", riderName).put("sha256", t.localSha256)
                .put("watchAddress", t.watchAddress).put("startRtcMs", t.startRtcMs)
                .put("activeMs", t.activeMs).put("durationS", t.durationS ?: JSONObject.NULL)
                .put("distanceM", t.distanceM ?: JSONObject.NULL).put("maxSpeedMs", t.maxSpeedMs ?: JSONObject.NULL)
                .put("segmentHashes", JSONObject().also { hashes -> files.forEach { f ->
                    val digest = MessageDigest.getInstance("SHA-256")
                    f.inputStream().use { input -> val buffer = ByteArray(8192); while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) } }
                    hashes.put(f.name, digest.digest().joinToString("") { "%02x".format(it) })
                } }).put("segments", files.size).toString()
            zip.putNextEntry(ZipEntry("manifest.json")); zip.write(manifest.toByteArray()); zip.closeEntry()
            files.forEach { file ->
                zip.putNextEntry(ZipEntry("segments/${file.name}"))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", target)
        Intent(Intent.ACTION_SEND).apply {
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, buildMessage(t, horseName, riderName))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    /** WhatsApp normally supports text plus a file, but the receiving app ultimately controls its display. */
    private fun buildMessage(t: TrainingEntity, horseName: String, riderName: String): String {
        val date = java.text.SimpleDateFormat("dd/MM/yyyy HH:mm", java.util.Locale("es", "ES"))
            .format(java.util.Date(t.startRtcMs))
        val distance = t.distanceM?.let { String.format(java.util.Locale("es", "ES"), "%.0f m", it) } ?: "—"
        val duration = t.durationS?.let { "${it.toLong() / 60} min ${it.toLong() % 60} s" } ?: "—"
        val vmax = t.maxSpeedMs?.let { String.format(java.util.Locale("es", "ES"), "%.1f km/h", it * 3.6) } ?: "—"
        return """🐎 *AVO PERFORMANCE HORSE*
            |━━━━━━━━━━━━━━━━━━
            |*ENTRENAMIENTO COMPARTIDO*
            |
            |🐴 *Caballo:* $horseName
            |🏇 *Jinete:* $riderName
            |📅 *Fecha:* $date
            |⏱ *Duración:* $duration
            |📍 *Distancia:* $distance
            |⚡ *Velocidad máxima:* $vmax
            |
            |📎 Archivo de telemetría AVO adjunto.
            |Abre el documento con AVO Performance Horse para consultar el análisis completo.
            |""".trimMargin()
    }
}
