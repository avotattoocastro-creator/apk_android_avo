package org.avoperformance.horse.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.AvoApp
import org.avoperformance.horse.ble.WatchConnection
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.WatchFileState
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.bytes.hexToBytes
import org.avoperformance.horse.core.bytes.toHex
import org.avoperformance.horse.core.raw.RawFileHeader
import org.avoperformance.horse.core.raw.TrainingAnalyzer
import org.avoperformance.horse.core.server.ServerApi
import org.avoperformance.horse.core.server.UploadResult
import org.avoperformance.horse.core.sync.LocalTraining
import org.avoperformance.horse.core.sync.SessionDownload
import org.avoperformance.horse.core.sync.SyncRules
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.data.AvoDatabase
import org.avoperformance.horse.data.Settings
import org.avoperformance.horse.data.TrainingEntity
import java.io.File
import java.util.concurrent.TimeUnit

data class SyncProgress(val sessionId: String? = null, val bytes: Long = 0, val total: Long = 0, val message: String? = null, val busy: Boolean = false)

/**
 * Watch trainings: list, resumable download, SHA-256 verification against the watch,
 * analysis, and (when a server exists) upload + MARK_UPLOADED.
 * Rules: never deletes anything on the watch automatically; "verificado" on the server
 * only with a real server confirmation; no download while the watch is recording.
 */
class WatchSyncManager(
    private val ctx: Context,
    private val db: AvoDatabase,
    private val settings: Settings,
    private val watch: WatchConnection,
    private val server: ServerApi,
    private val log: AppLog,
    private val scope: CoroutineScope,
) {
    private val _progress = MutableStateFlow(SyncProgress())
    val progress: StateFlow<SyncProgress> = _progress
    private val lock = Mutex()
    val trainingsDir: File get() = File(ctx.filesDir, "trainings").also { it.mkdirs() }
    val serverConfigured get() = server.configured

    private fun TrainingEntity.toLocal() = LocalTraining(sessionId, segments, totalBytes, downloadedBytes, localSha256, watchSha256, serverSha256,
        runCatching { SyncState.valueOf(state) }.getOrDefault(SyncState.EN_RELOJ), runCatching { WatchFileState.valueOf(watchState) }.getOrDefault(WatchFileState.UNKNOWN), startRtcMs, activeMs)

    private fun logEventMarine(sessionId: String, message: String?) {
        android.util.Log.w("AVO_MARINE", "Sin contexto marino para $sessionId: ${message ?: "sin datos"}")
    }

    private fun watchRecording() = watch.telemetry.value?.t?.session.let { it == WatchSessionState.RECORDING || it == WatchSessionState.PAUSED }

    /** Reads the session list from the watch and merges it (no duplicates: key = session id). */
    suspend fun refresh(): String? = lock.withLock {
        val c = watch.client ?: return "Sin conexión con el reloj"
        if (!watch.isReady) return "El reloj no está autorizado"
        _progress.value = SyncProgress(busy = true, message = "Leyendo lista del reloj…")
        try {
            val list = c.listSessions()
            val local = db.trainings().snapshot().associateBy { it.sessionId }
            val merged = SyncRules.merge(list, local.mapValues { it.value.toLocal() })
            for (m in merged) {
                val old = local[m.sessionId]
                db.trainings().upsert((old ?: TrainingEntity(m.sessionId, watch.authorizedAddress ?: "", m.segments, m.totalBytes, state = m.state.name,
                    watchState = m.watchState.name, startRtcMs = m.startRtcMs, activeMs = m.activeMs))
                    .copy(segments = m.segments, totalBytes = m.totalBytes, state = m.state.name, watchState = m.watchState.name,
                        startRtcMs = m.startRtcMs, activeMs = m.activeMs, updatedMs = System.currentTimeMillis()))
            }
            // Automatically enrich newly discovered recent trainings; never fabricate historical forecasts.
            val nowMs = System.currentTimeMillis()
            val recent = merged.filter { m -> m.startRtcMs > 0 &&
                kotlin.math.abs(nowMs - m.startRtcMs) < 2L * 60 * 60 * 1000 }
            if (recent.isNotEmpty()) scope.launch {
                for (m in recent) {
                    if (db.marine().byId(m.sessionId) != null) continue
                    runCatching {
                        val snapshot = org.avoperformance.horse.ui.screens.marineSnapshotForTraining(m.sessionId, m.startRtcMs)
                        db.marine().upsert(snapshot)
                    }.onFailure { logEventMarine(m.sessionId, it.message) }
                }
            }
            _progress.value = SyncProgress(message = "${list.size} entrenamientos en el reloj")
            null
        } catch (e: Exception) {
            _progress.value = SyncProgress(message = "Error: ${e.message}")
            e.message ?: "error"
        }
    }

    /** Downloads (resumable) and verifies one session. */
    @Volatile var isBusy: Boolean = false
        private set

    suspend fun download(sessionId: String): String? = lock.withLock {
        if (isBusy) return@withLock "Descarga ocupada"
        isBusy = true
        try { downloadLocked(sessionId) } finally { isBusy = false }
    }

    private suspend fun downloadLocked(sessionId: String): String? = withContext(Dispatchers.IO) {
        val c = watch.client ?: return@withContext "Sin conexión con el reloj"
        if (watchRecording()) return@withContext "El reloj está grabando: la descarga se hará al terminar"
        var t = db.trainings().byId(sessionId) ?: return@withContext "Entrenamiento desconocido"
        if (t.watchState == WatchFileState.OPEN.name) return@withContext "La sesión sigue abierta en el reloj"
        val dir = File(trainingsDir, sessionId)
        val dl = SessionDownload(dir, sessionId, maxOf(1, t.segments))
        t = t.copy(state = SyncState.DESCARGANDO.name, localDir = dir.absolutePath, lastError = null)
        db.trainings().upsert(t)
        try {
            var pos: Pair<Int, Long>? = dl.position()
            var lastSave = 0L
            while (pos != null) {
                if (watchRecording()) throw IllegalStateException("El reloj empezó a grabar: descarga en pausa")
                val chunk = c.readChunk(sessionId, pos.first, pos.second) ?: break   // no more segments
                pos = dl.append(pos.first, pos.second, chunk.data, chunk.fileSize)
                val got = dl.downloadedBytes()
                _progress.value = SyncProgress(sessionId, got, t.totalBytes, "Descargando", true)
                if (System.currentTimeMillis() - lastSave > 2000) { db.trainings().upsert(t.copy(downloadedBytes = got)); lastSave = System.currentTimeMillis() }
            }
            val got = dl.downloadedBytes()
            t = t.copy(downloadedBytes = got, state = SyncState.DESCARGADO.name)
            db.trainings().upsert(t)
            // Integrity: SHA-256 computed by the watch over the same segments
            _progress.value = SyncProgress(sessionId, got, t.totalBytes, "Verificando huella SHA-256 con el reloj…", true)
            val local = dl.sha256().toHex()
            val remote = c.fileSha256(sessionId).toHex()
            val ok = local == remote
            t = t.copy(localSha256 = local, watchSha256 = remote, state = (if (ok) SyncState.VERIFICADO_LOCAL else SyncState.ERROR_INTEGRIDAD).name,
                lastError = if (ok) null else "La huella local no coincide con la del reloj")
            db.trainings().upsert(t)
            log.i("SYNC", "$sessionId descargado ($got B) sha ${if (ok) "OK" else "DIFERENTE"}")
            if (ok) analyze(sessionId)
            _progress.value = SyncProgress(sessionId, got, t.totalBytes, if (ok) "Descargado y verificado" else "Error de integridad")
            if (ok) null else "Error de integridad"
        } catch (e: Exception) {
            db.trainings().upsert(t.copy(downloadedBytes = dl.downloadedBytes(), lastError = e.message))
            _progress.value = SyncProgress(sessionId, dl.downloadedBytes(), t.totalBytes, "Interrumpido: ${e.message} (se reanudará)")
            e.message ?: "error"
        }
    }

    /** Computes the metrics from the downloaded file (never from assumptions). */
    suspend fun analyze(sessionId: String) = withContext(Dispatchers.IO) {
        val t = db.trainings().byId(sessionId) ?: return@withContext
        val dir = File(t.localDir ?: return@withContext)
        val segs = SessionDownload(dir, sessionId, t.segments).segments()
        if (segs.isEmpty()) return@withContext
        val header = segs.first().inputStream().use { ins ->
            val b = ByteArray(RawFileHeader.SIZE); var n = 0
            while (n < b.size) { val k = ins.read(b, n, b.size - n); if (k < 0) break; n += k }
            RawFileHeader.decode(b)
        }
        val a = TrainingAnalyzer.analyze(segs.map { f -> { f.inputStream().buffered(256 * 1024) } })
        db.trainings().upsert(t.copy(horseCode = header?.horseName?.ifBlank { null }, riderCode = header?.riderName?.ifBlank { null },
            distanceM = a.distanceM, maxSpeedMs = a.maxSpeedMs, durationS = a.durationS, fixTimeS = a.fixTimeS, floatTimeS = a.floatTimeS,
            imuSamples = a.imuSamples, gnssUsable = a.gnssUsable))
    }

    fun analysisFor(t: TrainingEntity) = t.localDir?.let { d ->
        val segs = SessionDownload(File(d), t.sessionId, t.segments).segments()
        if (segs.isEmpty()) null else TrainingAnalyzer.analyze(segs.map { f -> { f.inputStream().buffered(256 * 1024) } })
    }

    /** Auto mode: download every closed session not yet on the phone. */
    fun autoSync() {
        if (!settings.autoDownload) return
        scope.launch(Dispatchers.IO) {
            if (refresh() != null) return@launch
            for (t in db.trainings().snapshot()) {
                val st = runCatching { SyncState.valueOf(t.state) }.getOrNull() ?: continue
                if ((st == SyncState.EN_RELOJ || st == SyncState.DESCARGANDO) && t.watchState != WatchFileState.OPEN.name) {
                    if (download(t.sessionId) != null) break
                }
            }
            uploadPending()
        }
    }

    /** Server step. While the server is on hold this only marks files as pending. */
    suspend fun uploadPending() = withContext(Dispatchers.IO) {
        for (t in db.trainings().snapshot()) {
            if (t.state != SyncState.VERIFICADO_LOCAL.name && t.state != SyncState.PENDIENTE_SERVIDOR.name && t.state != SyncState.VERIFICADO_SERVIDOR.name) continue
            if (t.state != SyncState.VERIFICADO_SERVIDOR.name) {
                val segs = SessionDownload(File(t.localDir ?: continue), t.sessionId, t.segments).segments()
                when (val r = server.uploadSession(t.sessionId, segs, t.localSha256 ?: continue, t.horseCode, t.riderCode)) {
                    is UploadResult.Confirmed -> {
                        val ok = r.serverSha256Hex.equals(t.localSha256, ignoreCase = true)
                        db.trainings().upsert(t.copy(serverSha256 = r.serverSha256Hex, state = (if (ok) SyncState.VERIFICADO_SERVIDOR else SyncState.ERROR_INTEGRIDAD).name))
                    }
                    UploadResult.NotConfigured -> db.trainings().upsert(t.copy(state = SyncState.PENDIENTE_SERVIDOR.name))
                    is UploadResult.Rejected -> db.trainings().upsert(t.copy(lastError = "Servidor: ${r.reason}"))
                    is UploadResult.NetworkError -> db.trainings().upsert(t.copy(lastError = "Red: ${r.reason}"))
                }
            }
            val now = db.trainings().byId(t.sessionId) ?: continue
            if (SyncRules.canMarkUploaded(now.toLocal()) && watch.isReady) {
                val st = watch.client?.markUploaded(now.sessionId, now.localSha256!!.hexToBytes())
                if (st == BleStatus.OK) db.trainings().upsert(now.copy(state = SyncState.MARCADO_EN_RELOJ.name, watchState = WatchFileState.UPLOADED.name))
                else log.w("SYNC", "MARK_UPLOADED ${now.sessionId}: ${st?.texto}")
            }
        }
    }

    /** Manual, confirmed by the user, only for sessions verified by the server and marked on the watch. */
    suspend fun deleteFromWatch(sessionId: String): String? {
        val t = db.trainings().byId(sessionId) ?: return "Entrenamiento desconocido"
        if (!SyncRules.canOfferDelete(t.toLocal())) return "Solo se pueden borrar del reloj entrenamientos verificados por el servidor"
        val st = watch.client?.deleteSession(sessionId) ?: return "Sin conexión con el reloj"
        if (st != BleStatus.OK) return "El reloj respondió: ${st.texto}"
        log.i("SYNC", "$sessionId borrado del reloj a petición del usuario")
        refresh()
        return null
    }

    fun scheduleWorker() {
        val req = PeriodicWorkRequestBuilder<SyncWorker>(1, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork("avo_sync", ExistingPeriodicWorkPolicy.KEEP, req)
    }
}

/** Background server sync of already verified files (no-op while the server is not configured). */
class SyncWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val c = (applicationContext as AvoApp).container
        return runCatching { c.sync.uploadPending(); Result.success() }.getOrElse { Result.retry() }
    }
}
