package org.avoperformance.horse.cloud

import android.net.Uri
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.BuildConfig
import org.avoperformance.horse.core.cloud.CloudSync
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.share.OfflineException
import org.avoperformance.horse.core.share.Packager
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Nube AVO: sube a Cloud Storage (plan Blaze) cada entrenamiento verificado con el reloj, como paquete .avo
 * (AVO-TRAINING-1), en `trainings/<CODIGO>/AVO_<id>.avo`. Solo lo ve el dueño de la tarjeta, desde cualquier app
 * (Android, iPad, Windows). Se ejecuta dentro de la pasada de [ShareManager] (mismas preferencias de red y reintentos).
 * Contrato y reglas: docs/NUBE_SESIONES.md y firebase/storage.rules.
 */
class CloudBackup(private val c: AppContainer, private val firebase: FirebaseShare) {
    data class Status(val uploaded: Int = 0, val pending: Int = 0, val total: Int = 0, val lastMs: Long = 0, val error: String? = null,
        /** Cambios de caballo/jinete traídos de la nube en la última pasada (hechos en el iPad o Windows). */
        val applied: Int = 0)
    data class Pass(val uploaded: Int, val pending: Int)

    private val _status = MutableStateFlow(Status(total = CloudSync.decode(c.settings.cloudUploaded).size))
    val status: StateFlow<Status> = _status

    private val storage: FirebaseStorage
        get() = FirebaseStorage.getInstance(firebase.firebaseApp, "gs://" + FirebaseConfig.STORAGE_BUCKET).apply {
            maxUploadRetryTimeMillis = 120_000
        }

    private data class Local(val sessionId: String, val fp: String?, val horse: String?, val rider: String?, val startRtcMs: Long)

    /**
     * Una pasada: sube lo pendiente (como mucho [max] subidas; el resto en la siguiente) y, cada hora, mira si en la nube
     * hay caballos/jinetes cambiados desde el iPad o Windows (gana el más reciente). Requiere la sesión ya abierta.
     */
    suspend fun sync(card: AvoUserCard, packager: Packager, max: Int = 5): Pass = withContext(Dispatchers.IO) {
        if (!c.settings.cloudEnabled) return@withContext Pass(0, 0)
        val horses = c.db.horses().all().first().associate { it.code to it.name }
        val riders = c.db.riders().all().first().associate { it.code to it.name }
        val locals = c.db.trainings().snapshot().mapNotNull { t ->
            val sha = t.localSha256 ?: return@mapNotNull null
            if (t.watchState == "IMPORTADO" || t.localDir == null || !sha.equals(t.watchSha256, true)) return@mapNotNull null
            val h = t.horseCode?.let(horses::get)?.takeIf { it.isNotBlank() }
            val r = t.riderCode?.let(riders::get)?.takeIf { it.isNotBlank() }
            val fp = if (h != null && r != null) CloudSync.fingerprint(sha, t.horseCode, t.riderCode, h, r) else null
            Local(t.sessionId, fp, h, r, t.startRtcMs)
        }
        val done = CloudSync.decode(c.settings.cloudUploaded).toMutableMap()
        val now = System.currentTimeMillis()
        val full = now - c.settings.cloudLastFullCheckMs > FULL_CHECK_MS
        // pendientes de subir (huella nueva) y, en la comprobación completa, todos (también los que aún no tienen caballo)
        val todo = locals.filter { full || (it.fp != null && done[it.sessionId] != it.fp) }.sortedByDescending { it.startRtcMs }
        var uploaded = 0; var applied = 0; var processed = 0
        var lastError: String? = null
        for (l in todo.take(if (full) 500 else max)) {
            if (uploaded >= max) break
            try {
                val ref = storage.reference.child(CloudSync.path(card.code, l.sessionId))
                val remote = try { remoteOf(await(ref.metadata)) } catch (e: StorageException) {
                    if (e.errorCode == StorageException.ERROR_OBJECT_NOT_FOUND) null else throw e
                }
                val localMs = org.avoperformance.horse.share.TrainingAssign.assignedMs(c, l.sessionId)
                when (CloudSync.decide(l.fp, localMs, l.horse, l.rider, remote)) {
                    CloudSync.Action.UPLOAD -> { upload(ref, l, localMs, packager); uploaded++; done[l.sessionId] = l.fp!! }
                    CloudSync.Action.APPLY_REMOTE -> {
                        val r = remote!!
                        val hn = r.horseName.orEmpty().trim(); val rn = r.riderName.orEmpty().trim()
                        val t = org.avoperformance.horse.share.TrainingAssign.assign(c, l.sessionId, hn, rn,
                            r.horseCode, r.riderCode, atMs = r.assignedMs, pushToCloud = false)
                        done[l.sessionId] = CloudSync.fingerprint(t.localSha256.orEmpty(), t.horseCode, t.riderCode, hn, rn)
                        applied++
                        c.log.i("CLOUD", "${l.sessionId}: caballo/jinete de la nube ($hn · $rn)")
                    }
                    CloudSync.Action.NOTHING -> l.fp?.let { done[l.sessionId] = it }
                }
                c.settings.cloudUploaded = CloudSync.encode(done)
                processed++
            } catch (e: OfflineException) {
                _status.value = _status.value.copy(error = null, lastMs = System.currentTimeMillis()); throw e
            } catch (e: Exception) {
                lastError = translate(e); c.log.w("CLOUD", "${l.sessionId}: $lastError")
                if (fatal(e)) break
            }
        }
        if (full && lastError == null && processed == todo.size.coerceAtMost(500)) c.settings.cloudLastFullCheckMs = now
        val pending = locals.count { it.fp != null && done[it.sessionId] != it.fp }
        _status.value = Status(uploaded, pending, done.size, System.currentTimeMillis(), lastError, applied)
        Pass(uploaded, pending)
    }

    private fun remoteOf(m: StorageMetadata) = CloudSync.Remote(
        m.getCustomMetadata("fp"), m.getCustomMetadata("assignedMs")?.toLongOrNull() ?: 0L,
        m.getCustomMetadata("horseCode"), m.getCustomMetadata("horseName"), m.getCustomMetadata("riderCode"), m.getCustomMetadata("riderName"))

    private suspend fun upload(ref: com.google.firebase.storage.StorageReference, l: Local, assignedMs: Long, packager: Packager) {
        val t = c.db.trainings().byId(l.sessionId) ?: error("Entrenamiento no encontrado")
        val p = packager.build(l.sessionId)
        try {
            if (p.size > CloudSync.MAX_BYTES) error("${l.sessionId}: ${p.size / 1_048_576} MB, supera el máximo de la nube (40 MB)")
            val meta = StorageMetadata.Builder().setContentType("application/octet-stream")
                .setCustomMetadata("sha256", p.sha256).setCustomMetadata("fp", l.fp.orEmpty())
                .setCustomMetadata("sessionId", l.sessionId)
                .setCustomMetadata("horseCode", t.horseCode.orEmpty()).setCustomMetadata("horseName", p.horseName)
                .setCustomMetadata("riderCode", t.riderCode.orEmpty()).setCustomMetadata("riderName", p.riderName)
                .setCustomMetadata("assignedMs", assignedMs.toString())
                .setCustomMetadata("startRtcMs", t.startRtcMs.toString())
                .setCustomMetadata("distanceM", t.distanceM?.let { "%.0f".format(java.util.Locale.ROOT, it) } ?: "")
                .setCustomMetadata("app", "android ${BuildConfig.VERSION_NAME}").build()
            await(ref.putFile(Uri.fromFile(p.file), meta), minutes = 15)
            c.settings.addShareUsage(p.size, 0)
            c.log.i("CLOUD", "${l.sessionId} subido a la nube (${p.size} B)")
        } finally { p.file.delete() }
    }

    /** Fuerza volver a comprobar todo (p. ej. tras reinstalar o cambiar de tarjeta). */
    fun forgetUploaded() { c.settings.cloudUploaded = ""; c.settings.cloudLastFullCheckMs = 0; _status.value = Status() }

    private fun <T> await(t: Task<T>, minutes: Long = 1): T = try { Tasks.await(t, minutes, TimeUnit.MINUTES) }
        catch (e: TimeoutException) { throw OfflineException("La nube no responde", e) }
        catch (e: ExecutionException) { throw (e.cause as? Exception) ?: e }

    private fun fatal(e: Exception) = e is StorageException && e.errorCode in setOf(
        StorageException.ERROR_NOT_AUTHORIZED, StorageException.ERROR_NOT_AUTHENTICATED, StorageException.ERROR_BUCKET_NOT_FOUND,
        StorageException.ERROR_PROJECT_NOT_FOUND, StorageException.ERROR_QUOTA_EXCEEDED)

    private fun translate(e: Exception): String = when {
        e is StorageException && e.errorCode == StorageException.ERROR_NOT_AUTHORIZED ->
            "Nube: permiso denegado. Publica firebase/storage.rules en la consola (Storage › Reglas)"
        e is StorageException && (e.errorCode == StorageException.ERROR_BUCKET_NOT_FOUND || e.errorCode == StorageException.ERROR_PROJECT_NOT_FOUND) ->
            "Nube: Storage no está activado (consola de Firebase › Storage, plan Blaze)"
        e is StorageException && e.errorCode == StorageException.ERROR_QUOTA_EXCEEDED -> "Nube: cuota superada (revisa el plan Blaze)"
        e is StorageException && e.errorCode == StorageException.ERROR_RETRY_LIMIT_EXCEEDED -> "Nube: sin conexión, se reintentará"
        else -> "Nube: ${e.message ?: e.javaClass.simpleName}"
    }

    private companion object { const val FULL_CHECK_MS = 60 * 60_000L }
}
