package org.avoperformance.horse.core.wifi

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import java.io.File
import java.io.IOException

/** Watch control over BLE (the app implements it with AvoClient; fake in tests). */
interface WatchWifiControl {
    sealed interface Start {
        data class Ok(val creds: WifiCredentials) : Start
        /** The watch refuses: recording, low battery, no SD, busy or radio error. */
        data class Refused(val reason: String, val retryLater: Boolean) : Start
        data object Unsupported : Start
    }
    suspend fun start(): Start
    suspend fun stop()
    fun recording(): Boolean
}

/** Connection to the watch network (WifiNetworkSpecifier in the app). null = not obtained (rejected/timeout). */
interface WifiConnector {
    suspend fun connect(creds: WifiCredentials): Link?
    interface Link : AutoCloseable { val http: WatchHttp }
}

/** What the app records when a training is complete and verified (Room, analysis, sharing). */
fun interface VerifiedSink { suspend fun onVerified(id: String, dir: File, sha256: String, bytes: Long) }

data class WifiSyncProgress(
    val state: WifiSyncState = WifiSyncState.IDLE,
    val sessionId: String? = null,
    val bytes: Long = 0, val total: Long = 0,
    val done: Int = 0, val pending: Int = 0,
    val message: String? = null,
) {
    val percent: Int get() = if (total > 0) ((bytes * 100) / total).toInt().coerceIn(0, 100) else 0
    /** Simple text for Entrenamientos. */
    val label: String get() = when (state) {
        WifiSyncState.DOWNLOADING -> "Descargando · $percent %"
        WifiSyncState.IDLE, WifiSyncState.CLEANUP -> ""
        else -> message ?: state.texto
    }
}

/** Result of a pass. [fallbackBle] = ids that must go over BLE (Wi-Fi unavailable or rejected). */
data class WifiSyncReport(val verified: List<String>, val failed: Map<String, String>, val fallbackBle: List<String>, val skipped: Boolean = false)

/**
 * IDLE → DISCOVERING → WIFI_STARTING → CONNECTING → DOWNLOADING → VERIFYING → COMPLETED → CLEANUP (→ IDLE)
 * with WAITING (retry later), CANCELLED, ERROR and PAUSED. A single pass at a time (a second one is not queued:
 * it returns skipped). The Wi-Fi of the watch is always turned off when finishing (finally), even with errors.
 */
class WifiSyncCoordinator(
    private val control: WatchWifiControl,
    private val connector: WifiConnector,
    private val dirFor: (String) -> File,
    private val sink: VerifiedSink,
    private val log: (String) -> Unit = {},
) {
    private val running = Mutex()
    private val _progress = MutableStateFlow(WifiSyncProgress())
    val progress: StateFlow<WifiSyncProgress> = _progress
    @Volatile private var cancelRequested = false
    @Volatile var paused = false

    fun cancel() { cancelRequested = true }
    val busy get() = running.isLocked

    /** [pending]: id → SHA already verified locally (null if not downloaded). */
    suspend fun sync(pending: List<Pair<String, String?>>): WifiSyncReport {
        if (pending.isEmpty()) return WifiSyncReport(emptyList(), emptyMap(), emptyList())
        if (!running.tryLock()) return WifiSyncReport(emptyList(), emptyMap(), emptyList(), skipped = true)
        cancelRequested = false
        val verified = ArrayList<String>(); val failed = LinkedHashMap<String, String>()
        var started = false
        var link: WifiConnector.Link? = null
        val ids = pending.map { it.first }
        try {
            if (paused) { set(WifiSyncState.PAUSED); return WifiSyncReport(emptyList(), emptyMap(), emptyList(), skipped = true) }
            if (control.recording()) { set(WifiSyncState.WAITING, msg = "Pendiente: el reloj está grabando"); return WifiSyncReport(emptyList(), ids.associateWith { "grabando" }, emptyList()) }
            set(WifiSyncState.WIFI_STARTING, pending = ids.size)
            val creds = when (val s = try { control.start() } catch (e: Exception) { WatchWifiControl.Start.Refused(e.message ?: "BLE", true) }) {
                is WatchWifiControl.Start.Ok -> s.creds
                WatchWifiControl.Start.Unsupported -> { log("wifi: firmware sin Wi-Fi → BLE"); return WifiSyncReport(emptyList(), emptyMap(), ids) }
                is WatchWifiControl.Start.Refused -> {
                    log("wifi: rechazado (${s.reason})")
                    set(WifiSyncState.WAITING, msg = "Pendiente de conexión")
                    return if (s.retryLater) WifiSyncReport(emptyList(), ids.associateWith { s.reason }, emptyList())
                           else WifiSyncReport(emptyList(), emptyMap(), ids)
                }
            }
            started = true
            set(WifiSyncState.CONNECTING, pending = ids.size)
            link = connector.connect(creds)
            if (link == null) { log("wifi: Android no conectó → BLE"); return WifiSyncReport(emptyList(), emptyMap(), ids) }
            val dl = WifiDownloader(link.http, dirFor) { cancelRequested || control.recording() }
            for ((n, p) in pending.withIndex()) {
                val (id, localSha) = p
                if (cancelRequested) { set(WifiSyncState.CANCELLED); break }
                if (control.recording()) { set(WifiSyncState.WAITING, msg = "Pendiente: el reloj está grabando"); failed[id] = "grabando"; break }
                set(WifiSyncState.DOWNLOADING, id, done = n, pending = ids.size)
                val r = try {
                    dl.download(id, localSha) { b, t -> _progress.value = _progress.value.copy(state = WifiSyncState.DOWNLOADING, sessionId = id, bytes = b, total = t) }
                } catch (e: RecordingException) { failed[id] = "grabando"; break }
                  catch (e: AuthException) { failed[id] = e.message ?: "token"; break }
                  catch (e: ChangedException) { failed[id] = "El fichero cambió; se repetirá"; continue }
                  catch (e: IOException) { failed[id] = e.message ?: "conexión"; log("wifi: $id ${e.message}"); break }
                when (r) {
                    is DownloadResult.Verified -> {
                        set(WifiSyncState.VERIFYING, id, done = n, pending = ids.size)
                        sink.onVerified(id, dirFor(id), r.sha256, r.bytes)
                        runCatching { link.http.complete(id, r.sha256, done = false) }
                        verified += id
                        set(WifiSyncState.COMPLETED, id, done = n + 1, pending = ids.size)
                    }
                    DownloadResult.AlreadyLocal -> verified += id
                    DownloadResult.NotReady -> failed[id] = "sesión abierta en el reloj"
                    is DownloadResult.Mismatch -> failed[id] = "Huella SHA-256 distinta"
                    DownloadResult.Cancelled -> { if (control.recording()) failed[id] = "grabando"; set(WifiSyncState.CANCELLED); break }
                }
            }
            if (verified.size == ids.size) runCatching { link.http.complete(ids.last(), "", done = true) }
            // what did not finish (interruption) is left for the next pass; partial data is kept
            return WifiSyncReport(verified, failed + ids.filter { it !in verified && it !in failed }.associateWith { "pendiente" }, emptyList())
        } finally {
            set(WifiSyncState.CLEANUP)
            runCatching { link?.close() }
            if (started) runCatching { control.stop() }
            val last = _progress.value
            _progress.value = WifiSyncProgress(
                state = when {
                    cancelRequested -> WifiSyncState.CANCELLED
                    verified.size == ids.size -> WifiSyncState.COMPLETED
                    failed.isNotEmpty() -> WifiSyncState.WAITING
                    else -> WifiSyncState.IDLE
                },
                done = verified.size, pending = ids.size,
                message = if (verified.size == ids.size) "Entrenamiento guardado ✓" else if (failed.isNotEmpty()) "Pendiente de conexión" else last.message)
            running.unlock()
        }
    }

    private fun set(s: WifiSyncState, id: String? = null, done: Int = _progress.value.done, pending: Int = _progress.value.pending, msg: String? = null) {
        _progress.value = WifiSyncProgress(s, id, 0, 0, done, pending, msg)
    }
}
