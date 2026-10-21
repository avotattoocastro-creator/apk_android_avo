package org.avoperformance.horse.share

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.data.HorseEntity
import org.avoperformance.horse.data.RiderEntity
import org.avoperformance.horse.data.TrainingEntity
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile

/** Untrusted .avo imports: stage, validate and ask before replacing an existing session. */
object TrainingImport {
    data class Preview(val staged: File, val sessionId: String, val horseCode: String, val riderCode: String,
                       val horseName: String, val riderName: String, val sha256: String, val manifest: JSONObject, val duplicate: Boolean,
                       val identical: Boolean)

    suspend fun inspect(c: AppContainer, uri: Uri): Preview = withContext(Dispatchers.IO) {
        val staged = File.createTempFile("avo_received_", ".avo", c.app.cacheDir)
        try {
            c.app.contentResolver.openInputStream(uri)?.use { source ->
                staged.outputStream().use { dest ->
                    val buf = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val n = source.read(buf)
                        if (n < 0) break
                        total += n
                        require(total <= 100L * 1024 * 1024) { "Archivo demasiado grande (máximo 100 MB)" }
                        dest.write(buf, 0, n)
                    }
                }
            } ?: error("No se puede abrir el documento")
            val manifest = ZipFile(staged).use { zip ->
                require(zip.size() in 2..400) { "Número de entradas no válido" }
                val entry = zip.getEntry("manifest.json") ?: error("No contiene manifest.json")
                require(entry.size in 1..16384) { "Manifiesto de tamaño no válido" }
                JSONObject(zip.getInputStream(entry).bufferedReader().use { it.readText() })
            }
            require(manifest.optString("format") == "AVO-TRAINING-1") { "Formato AVO no compatible" }
            val id = manifest.getString("sessionId").trim()
            require(id.length in 3..128 && !id.contains('/') && !id.contains('\\')) { "ID de sesión no válido" }
            val horse = manifest.getString("horseName").trim()
            val rider = manifest.getString("riderName").trim()
            require(horse.isNotBlank() && rider.isNotBlank() && horse.length <= 120 && rider.length <= 120) { "Faltan caballo o jinete" }
            val sha = manifest.getString("sha256").lowercase()
            require(sha.matches(Regex("[a-f0-9]{64}"))) { "Huella SHA-256 no válida" }
            val old = c.db.trainings().byId(id)
            Preview(staged, id, manifest.optString("horseCode"), manifest.optString("riderCode"),
                horse, rider, sha, manifest, old != null, old?.localSha256.equals(sha, true))
        } catch (t: Throwable) { staged.delete(); throw t }
    }

    suspend fun import(c: AppContainer, p: Preview): String = withContext(Dispatchers.IO) {
        val original = c.db.trainings().byId(p.sessionId)
        if (p.identical) { p.staged.delete(); return@withContext "El entrenamiento ya existe y es idéntico" }
        val dest = File(c.app.filesDir, "received/${p.sessionId.replace(Regex("[^A-Za-z0-9_-]"), "_")}")
        val temp = File(c.app.filesDir, "received/.staging_${System.nanoTime()}")
        temp.mkdirs()
        try {
            var count = 0
            var total = 0L
            val hashes = p.manifest.optJSONObject("segmentHashes") ?: error("Este paquete no contiene verificaciones por segmento; vuelve a exportarlo con V1.8")
            require(hashes.length() == p.manifest.getInt("segments")) { "Cantidad de hashes incorrecta" }
            ZipFile(p.staged).use { zip ->
                val entries = zip.entries()
                while (entries.hasMoreElements()) {
                    val e = entries.nextElement()
                    if (e.name == "manifest.json") continue
                    require(!e.isDirectory && e.name.startsWith("segments/") && e.name.removePrefix("segments/").matches(Regex("[A-Za-z0-9_.-]{1,120}"))) { "Ruta del archivo no válida" }
                    require(e.size in 1..(50L * 1024 * 1024)) { "Segmento de tamaño no válido" }
                    val output = File(temp, e.name.removePrefix("segments/"))
                    require(!output.exists()) { "Segmento duplicado" }
                    val declaredHash = hashes.optString(output.name).lowercase()
                    require(declaredHash.matches(Regex("[a-f0-9]{64}"))) { "Falta hash del segmento" }
                    val digest = MessageDigest.getInstance("SHA-256")
                    zip.getInputStream(e).use { input ->
                        output.outputStream().use { stream ->
                            val buffer = ByteArray(8192)
                            var written = 0L
                            while (true) {
                                val n = input.read(buffer)
                                if (n < 0) break
                                written += n
                                require(written <= 50L * 1024 * 1024) { "Segmento demasiado grande" }
                                digest.update(buffer, 0, n)
                                stream.write(buffer, 0, n)
                            }
                            require(written == e.size) { "Longitud del segmento incorrecta" }
                            require(digest.digest().joinToString("") { "%02x".format(it) } == declaredHash) { "SHA-256 del segmento incorrecto" }
                            total += written
                        }
                    }
                    count++
                }
            }
            require(count > 0 && count == p.manifest.getInt("segments")) { "Paquete incompleto" }
            // Watch's SHA-256 is a canonical training digest. Preserve it as metadata;
            // do not falsely claim ZIP SHA-256 equals the original watch digest.
            val horses = c.db.horses().all().first()
            val riders = c.db.riders().all().first()
            val horseCode = p.horseCode.takeIf { it.isNotBlank() } ?: "IMPH_${shaCode(p.horseName)}"
            val riderCode = p.riderCode.takeIf { it.isNotBlank() } ?: "IMPR_${shaCode(p.riderName)}"
            val existingHorse = horses.firstOrNull { it.code == horseCode || it.name.equals(p.horseName, true) }
            val existingRider = riders.firstOrNull { it.code == riderCode || it.name.equals(p.riderName, true) }
            // Avoid deleting existing data until the replacement is validated.
            val backup = if (dest.exists()) File(dest.parentFile, ".backup_${System.nanoTime()}") else null
            if (backup != null) require(dest.renameTo(backup)) { "No se pudo preservar la versión anterior" }
            try {
                require(temp.renameTo(dest)) { "No se pudo instalar el entrenamiento" }
                if (existingHorse == null) c.db.horses().insert(HorseEntity(code = horseCode, name = p.horseName))
                if (existingRider == null) c.db.riders().insert(RiderEntity(code = riderCode, name = p.riderName))
                c.db.trainings().upsert((original ?: TrainingEntity(
                    sessionId = p.sessionId, watchAddress = "importado", segments = count,
                    totalBytes = total, state = "VERIFICADO_LOCAL", watchState = "IMPORTADO",
                    startRtcMs = p.manifest.optLong("startRtcMs", System.currentTimeMillis()), activeMs = p.manifest.optLong("activeMs", 0)
                )).copy(segments = count, totalBytes = total, downloadedBytes = total,
                    localDir = dest.absolutePath, localSha256 = p.sha256,
                    watchSha256 = p.sha256, horseCode = existingHorse?.code ?: horseCode,
                    riderCode = existingRider?.code ?: riderCode, state = "VERIFICADO_LOCAL",
                    lastError = null, updatedMs = System.currentTimeMillis(),
                    distanceM = p.manifest.optDouble("distanceM").takeUnless { it.isNaN() } ?: original?.distanceM,
                    durationS = p.manifest.optDouble("durationS").takeUnless { it.isNaN() } ?: original?.durationS,
                    maxSpeedMs = p.manifest.optDouble("maxSpeedMs").takeUnless { it.isNaN() } ?: original?.maxSpeedMs))
                backup?.deleteRecursively()
            } catch (t: Throwable) {
                dest.deleteRecursively()
                if (backup != null) backup.renameTo(dest)
                throw t
            }
            "Entrenamiento importado: ${p.horseName} · ${p.riderName}"
        } finally { temp.deleteRecursively(); p.staged.delete() }
    }

    fun discard(p: Preview) { p.staged.delete() }
    private fun shaCode(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.lowercase().trim().toByteArray()).take(7).joinToString("") { "%02x".format(it) }
}
