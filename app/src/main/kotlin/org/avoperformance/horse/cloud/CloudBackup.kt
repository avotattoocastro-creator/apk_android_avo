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
    data class Status(val uploaded: Int = 0, val pending: Int = 0, val total: Int = 0, val lastMs: Long = 0, val error: String? = null)
    data class Pass(val uploaded: Int, val pending: Int)

    private val _status = MutableStateFlow(Status(total = CloudSync.decode(c.settings.cloudUploaded).size))
    val status: StateFlow<Status> = _status

    private val storage: FirebaseStorage
        get() = FirebaseStorage.getInstance(firebase.firebaseApp, "gs://" + FirebaseConfig.STORAGE_BUCKET).apply {
            maxUploadRetryTimeMillis = 120_000
        }

    /** Sube lo pendiente (como mucho [max] por pasada; el resto en la siguiente). Requiere la sesión ya abierta. */
    suspend fun sync(card: AvoUserCard, packager: Packager, max: Int = 5): Pass = withContext(Dispatchers.IO) {
        if (!c.settings.cloudEnabled) return@withContext Pass(0, 0)
        val horses = c.db.horses().all().first().associate { it.code to it.name }
        val riders = c.db.riders().all().first().associate { it.code to it.name }
        val candidates = c.db.trainings().snapshot().mapNotNull { t ->
            val sha = t.localSha256 ?: return@mapNotNull null
            if (t.watchState == "IMPORTADO" || t.localDir == null || !sha.equals(t.watchSha256, true)) return@mapNotNull null
            val h = t.horseCode?.let(horses::get)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val r = t.riderCode?.let(riders::get)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            CloudSync.Candidate(t.sessionId, CloudSync.fingerprint(sha, t.horseCode, t.riderCode, h, r), t.startRtcMs)
        }
        val done = CloudSync.decode(c.settings.cloudUploaded).toMutableMap()
        val todo = CloudSync.pending(candidates, done)
        var uploaded = 0
        var processed = 0
        var lastError: String? = null
        for (cand in todo.take(max)) {
            try {
                val ref = storage.reference.child(CloudSync.path(card.code, cand.sessionId))
                val remoteFp = try { await(ref.metadata).getCustomMetadata("fp") } catch (e: StorageException) {
                    if (e.errorCode == StorageException.ERROR_OBJECT_NOT_FOUND) null else throw e
                }
                if (remoteFp != cand.fingerprint) {
                    val t = c.db.trainings().byId(cand.sessionId) ?: continue
                    val p = packager.build(cand.sessionId)
                    try {
                        if (p.size > CloudSync.MAX_BYTES) error("${cand.sessionId}: ${p.size / 1_048_576} MB, supera el máximo de la nube (40 MB)")
                        val meta = StorageMetadata.Builder().setContentType("application/octet-stream")
                            .setCustomMetadata("sha256", p.sha256).setCustomMetadata("fp", cand.fingerprint)
                            .setCustomMetadata("sessionId", cand.sessionId).setCustomMetadata("horseName", p.horseName)
                            .setCustomMetadata("riderName", p.riderName).setCustomMetadata("startRtcMs", t.startRtcMs.toString())
                            .setCustomMetadata("distanceM", t.distanceM?.let { "%.0f".format(java.util.Locale.ROOT, it) } ?: "")
                            .setCustomMetadata("app", "android ${BuildConfig.VERSION_NAME}").build()
                        await(ref.putFile(Uri.fromFile(p.file), meta), minutes = 15)
                        c.settings.addShareUsage(p.size, 0)
                        uploaded++
                        c.log.i("CLOUD", "${cand.sessionId} subido a la nube (${p.size} B)")
                    } finally { p.file.delete() }
                }
                done[cand.sessionId] = cand.fingerprint
                c.settings.cloudUploaded = CloudSync.encode(done)
                processed++
            } catch (e: OfflineException) {
                _status.value = _status.value.copy(error = null, lastMs = System.currentTimeMillis()); throw e
            } catch (e: Exception) {
                lastError = translate(e); c.log.w("CLOUD", "${cand.sessionId}: $lastError")
                if (fatal(e)) break
            }
        }
        val pending = todo.size - processed
        _status.value = Status(uploaded, pending, done.size, System.currentTimeMillis(), lastError)
        Pass(uploaded, pending)
    }

    /** Fuerza volver a comprobar todo (p. ej. tras reinstalar o cambiar de tarjeta). */
    fun forgetUploaded() { c.settings.cloudUploaded = ""; _status.value = Status() }

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
}
