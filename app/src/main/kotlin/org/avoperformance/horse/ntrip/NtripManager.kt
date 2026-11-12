package org.avoperformance.horse.ntrip

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.ble.WatchConnection
import org.avoperformance.horse.core.ble.Requests
import org.avoperformance.horse.core.ntrip.Gga
import org.avoperformance.horse.core.ntrip.MountChoice
import org.avoperformance.horse.core.ntrip.MountSelector
import org.avoperformance.horse.core.ntrip.RankedMount
import org.avoperformance.horse.core.ntrip.SourceEntry
import org.avoperformance.horse.core.ntrip.GgaPosition
import org.avoperformance.horse.core.ntrip.NtripClient
import org.avoperformance.horse.core.ntrip.NtripState
import org.avoperformance.horse.core.ntrip.NtripStats
import org.avoperformance.horse.core.rtcm.RtcmFramer
import org.avoperformance.horse.core.rtcm.RtcmPacer
import org.avoperformance.horse.core.rtcm.RtcmStats
import org.avoperformance.horse.data.Settings
import kotlin.concurrent.thread

data class RtcmPathStats(
    val framer: RtcmStats = RtcmStats(),
    val sentBytes: Long = 0, val sentWrites: Long = 0, val queuedBytes: Int = 0,
    val droppedStale: Long = 0, val droppedOverflow: Long = 0, val writeRefused: Long = 0,
    val watchDropped: Long = 0, val watchFree: Long? = null, val lastAckAgeMs: Long? = null,
)

/**
 * NTRIP caster → RTCM3 framing → paced BLE writes to the watch.
 * Correction bytes are never modified; anything discarded is counted.
 * RTK state shown to the user comes ONLY from the watch telemetry (receiver).
 */
class NtripManager(
    private val settings: Settings,
    private val watch: WatchConnection,
    private val log: AppLog,
    private val scope: CoroutineScope,
    /** Where the caster sourcetable is cached (automatic mountpoint selection). */
    private val cacheDir: java.io.File? = null,
) {
    private val _state = MutableStateFlow<NtripState>(NtripState.Stopped)
    val state: StateFlow<NtripState> = _state
    private val _stats = MutableStateFlow(NtripStats())
    val stats: StateFlow<NtripStats> = _stats
    private val _path = MutableStateFlow(RtcmPathStats())
    val path: StateFlow<RtcmPathStats> = _path

    private var client: NtripClient? = null
    private var sender: Job? = null
    private val framer = RtcmFramer()
    private val pacer = RtcmPacer(maxChunk = Requests.rtcmMaxChunk(20))
    private var refused = 0L
    private var lastFree: Long? = null

    val running get() = client != null

    /** Mountpoint in use (main or backup). Null while stopped. */
    private val _activeMount = MutableStateFlow<String?>(null)
    val activeMount: StateFlow<String?> = _activeMount
    private var mountIndex = 0          // 0 = main, 1.. = backups
    private var failsInRow = 0
    private var lastDataMs = 0L
    private var watchdog: Job? = null

    // ---- automatic selection by position
    @Volatile private var entries: List<SourceEntry> = emptyList()
    @Volatile private var entriesMs = 0L
    @Volatile private var autoList: List<String> = emptyList()
    private val _choice = MutableStateFlow<MountChoice?>(null)
    /** Current automatic choice (main mountpoint, distance and why). Null in manual mode or before a choice. */
    val choice: StateFlow<MountChoice?> = _choice
    private val _ranking = MutableStateFlow<List<RankedMount>>(emptyList())
    /** Usable mountpoints of the caster ranked for the last known position (for the settings screen). */
    val ranking: StateFlow<List<RankedMount>> = _ranking
    private val _autoNote = MutableStateFlow<String?>(null)
    val autoNote: StateFlow<String?> = _autoNote
    private var lastSavedPosMs = 0L
    @Volatile private var lastFailoverMs = 0L

    private val auto get() = settings.ntrip.value.autoSelect

    /** Mountpoints in order of preference: automatic list, or main + backups from the settings. */
    private fun mounts(): List<String> {
        if (auto && autoList.isNotEmpty()) return autoList
        return (listOf(settings.ntrip.value.mountpoint.trim()) + settings.ntrip.value.backups()).filter { it.isNotEmpty() }
    }

    private fun cacheFile() = cacheDir?.let { java.io.File(it, "ntrip_sourcetable_${settings.ntrip.value.host.hashCode()}_${settings.ntrip.value.port}.txt") }

    /** Sourcetable of the configured caster: memory → disk cache (24 h) → network. Stale cache is used offline. */
    private fun loadEntries(force: Boolean = false): List<SourceEntry> {
        val now = System.currentTimeMillis()
        if (!force && entries.isNotEmpty() && now - entriesMs < 24 * 3_600_000L) return entries
        val f = cacheFile()
        if (!force && f != null && f.exists() && now - f.lastModified() < 24 * 3_600_000L) {
            SourceEntry.parseAll(f.readText()).takeIf { it.isNotEmpty() }?.let { entries = it; entriesMs = f.lastModified(); return it }
        }
        return try {
            val text = NtripClient.fetchSourcetableText(settings.ntripConfig())
            val parsed = SourceEntry.parseAll(text)
            if (parsed.isNotEmpty()) { f?.writeText(text); entries = parsed; entriesMs = now; log.i("NTRIP", "lista del caster: ${parsed.size} mountpoints") }
            parsed.ifEmpty { entries }
        } catch (e: Exception) {
            log.w("NTRIP", "no se pudo leer la lista del caster: ${e.message}")
            if (entries.isEmpty() && f != null && f.exists()) entries = SourceEntry.parseAll(f.readText())
            entries
        }
    }

    /** Receiver position (fresh fix) or, failing that, the last one saved. */
    private fun position(): Pair<Double, Double>? = ggaPosition()?.let { it.lat to it.lon } ?: settings.ntripLastPosition

    private fun recording(): Boolean {
        val s = watch.telemetry.value?.t?.session
        return s == org.avoperformance.horse.core.ble.WatchSessionState.RECORDING || s == org.avoperformance.horse.core.ble.WatchSessionState.PAUSED
    }

    /** Computes the automatic choice for the current position. Returns null when there is nothing to choose with. */
    private fun evaluate(current: String?): MountChoice? {
        val list = loadEntries()
        if (list.isEmpty()) { _autoNote.value = "Sin lista de mountpoints del caster (revisa servidor y usuario)"; return null }
        val pos = position()
        if (pos == null) {
            // no position yet: a network/VRS mountpoint works anywhere (it uses the GGA sent later)
            val net = list.firstOrNull { it.isRtcm3 && it.network }
            _autoNote.value = "Esperando posición GPS" + (net?.let { "; mientras tanto, red ${it.mountpoint}" } ?: "")
            return net?.let { MountChoice(listOf(it.mountpoint), it, null, "sin posición todavía: red / VRS") }
        }
        _ranking.value = MountSelector.rank(list, pos.first, pos.second).take(8)
        val c = MountSelector.choose(list, pos.first, pos.second, current, settings.ntrip.value.autoMaxKm)
        _autoNote.value = if (c == null) "El caster no tiene mountpoints RTCM 3" else null
        return c
    }

    /** Re-checks the choice; switches source only when not recording (a switch restarts RTK convergence). */
    @Synchronized
    private fun reevaluate(forceStart: Boolean = false) {
        if (!auto) { _choice.value = null; return }
        ggaPosition()?.let { p ->
            val now = System.currentTimeMillis()
            if (now - lastSavedPosMs > 60_000) { settings.ntripLastPosition = p.lat to p.lon; lastSavedPosMs = now }
        }
        val active = _activeMount.value
        val c = evaluate(active) ?: return
        _choice.value = c
        val newMain = c.ordered.first()
        if (client == null) {
            if (forceStart || _state.value is NtripState.Failed) { autoList = c.ordered; log.i("NTRIP", "automático: $newMain (${c.reason})"); startOn(0) }
            return
        }
        if (newMain == active) { autoList = c.ordered; return }
        // after a failover (main without corrections) stay on the backup for 10 min before trying the main again
        if (active != null && active in c.ordered && System.currentTimeMillis() - lastFailoverMs < 10 * 60_000L) return
        if (recording()) { _autoNote.value = "Mejor fuente: $newMain (${c.reason}); se cambiará al terminar la grabación"; return }
        log.i("NTRIP", "automático: cambio de $active a $newMain (${c.reason})")
        autoList = c.ordered
        client?.stop(); client = null
        synchronized(pacer) { pacer.clear() }
        startOn(0)
    }

    fun start() {
        if (!org.avoperformance.horse.license.LicenseGate.canRecord) return
        if (client != null) return
        mountIndex = 0
        watchdog?.cancel()
        if (auto) {
            _state.value = NtripState.Connecting(0)
            watchdog = scope.launch(Dispatchers.IO) {
                reevaluate(forceStart = true)
                if (client == null && mounts().isNotEmpty()) startOn(0)   // no automatic choice: manual mountpoint, if any
                if (client == null) _state.value = NtripState.Failed(_autoNote.value ?: "Sin mountpoint")
                failoverLoop()
            }
        } else {
            startOn(0)
            watchdog = scope.launch { failoverLoop() }
        }
    }

    /** Forces a fresh sourcetable and a new automatic choice (settings screen). */
    fun refreshAuto() = scope.launch(Dispatchers.IO) { loadEntries(force = true); reevaluate(forceStart = client == null && auto) }

    /**
     * Automatic failover: a mountpoint that fails 3 connections in a row, or streams nothing for 30 s, is replaced
     * by the next one in the list (main → backups → main). Only one source at a time: corrections from different
     * bases are never mixed in the receiver.
     */
    private suspend fun failoverLoop() {
        var lastAuto = System.currentTimeMillis()
        var hadFix = ggaPosition() != null
        while (true) {
            delay(1000)
            if (auto) {
                // every minute, at the first fix and right after a recording ends
                val fix = ggaPosition() != null
                val now = System.currentTimeMillis()
                if (now - lastAuto >= 60_000 || (fix && !hadFix)) {
                    lastAuto = now
                    runCatching { kotlinx.coroutines.withContext(Dispatchers.IO) { reevaluate() } }
                        .onFailure { log.w("NTRIP", "selección automática: ${it.message}") }
                }
                hadFix = fix
            }
            val list = mounts()
            if (client == null || list.size < 2) continue
            val st = _state.value
            val silent = st is NtripState.Streaming && lastDataMs > 0 && System.currentTimeMillis() - lastDataMs > 30_000
            if (failsInRow >= 3 || silent) {
                val from = list.getOrNull(mountIndex)
                val next = (mountIndex + 1) % list.size
                lastFailoverMs = System.currentTimeMillis()
                log.w("NTRIP", "fuente ${from ?: "?"} sin correcciones (${if (silent) "30 s sin datos" else "$failsInRow fallos seguidos"}): cambio a ${list[next]}")
                client?.stop(); client = null
                synchronized(pacer) { pacer.clear() }
                startOn(next)
            }
        }
    }

    private fun startOn(index: Int) {
        val list = mounts()
        if (list.isEmpty()) { _state.value = NtripState.Failed(if (auto) (_autoNote.value ?: "Esperando posición GPS") else "Falta el mountpoint"); return }
        mountIndex = index.coerceIn(0, list.lastIndex)
        failsInRow = 0
        lastDataMs = 0L
        val cfg = settings.ntripConfig().copy(mountpoint = list[mountIndex])
        _activeMount.value = cfg.mountpoint
        val problems = cfg.problems()
        if (problems.isNotEmpty()) { _state.value = NtripState.Failed(problems.joinToString("; ")); return }
        watch.rtcmAckListener = { a ->
            synchronized(pacer) { pacer.onAck(a.freeBytes, a.expectedSeq, a.droppedBytes, System.currentTimeMillis()) }
            lastFree = a.freeBytes
        }
        val c = NtripClient(cfg, ::ggaPosition,
            onData = { b, o, n ->
                lastDataMs = System.currentTimeMillis()
                val frames = synchronized(framer) { framer.feed(b, o, n) }
                val now = System.currentTimeMillis()
                synchronized(pacer) { frames.forEach { pacer.offer(it, now) } }
            },
            onState = {
                _state.value = it; log.i("NTRIP", "${cfg.mountpoint}: ${it.texto}")
                when (it) { is NtripState.Streaming -> failsInRow = 0; is NtripState.WaitingRetry -> failsInRow++; else -> {} }
            },
            onStats = { _stats.value = it })
        client = c
        thread(name = "avo-ntrip", isDaemon = true) { c.run(); if (client === c) client = null }
        if (sender == null) sender = scope.launch(Dispatchers.IO) { sendLoop() }
    }

    fun stop() {
        watchdog?.cancel(); watchdog = null
        autoList = emptyList()
        _activeMount.value = null
        client?.stop()
        client = null
        sender?.cancel()
        sender = null
        synchronized(pacer) { pacer.clear() }
        _state.value = NtripState.Stopped
    }

    private suspend fun sendLoop() {
        var linkWasReady = false
        while (true) {   // cancelled through delay()/suspending writes when the job is cancelled
            val bc = watch.client
            val ready = watch.isReady && bc != null
            if (!ready) { linkWasReady = false; delay(200); publish(); continue }
            if (watch.downloadMode.value) {
                // download mode: the link is reserved for the file transfer. Corrections are not forwarded (they would be
                // stale anyway); the caster connection stays open and forwarding restarts cleanly afterwards.
                linkWasReady = false
                synchronized(pacer) { pacer.clear() }
                delay(200); publish(); continue
            }
            if (!linkWasReady) { synchronized(pacer) { pacer.onReconnect(); pacer.maxChunk = Requests.rtcmMaxChunk(watch.mtu.value?.minus(3) ?: 20) }; linkWasReady = true }
            val next = synchronized(pacer) { pacer.next(System.currentTimeMillis()) }
            if (next == null) { delay(20); publish(); continue }
            val ok = runCatching { bc!!.writeRtcm(next.first, next.second) }.getOrDefault(false)
            if (ok) synchronized(pacer) { pacer.onSent(next.second.size) }
            else { refused++; delay(30) }   // the same chunk is retried (not committed)
            publish()
        }
    }

    private var lastPublish = 0L
    private fun publish() {
        val now = System.currentTimeMillis()
        if (now - lastPublish < 500) return
        lastPublish = now
        _path.value = synchronized(pacer) {
            RtcmPathStats(synchronized(framer) { framer.stats }, pacer.sentBytes, pacer.sentWrites, pacer.queued(),
                pacer.droppedStaleBytes, pacer.droppedOverflowBytes, refused, pacer.watchReportedDropped, lastFree,
                if (pacer.lastAckMs == 0L) null else now - pacer.lastAckMs)
        }
    }

    /** GGA from the receiver position reported by the watch (only when it has a valid fix and is fresh). */
    private fun ggaPosition(): GgaPosition? {
        val s = watch.telemetry.value ?: return null
        if (System.currentTimeMillis() - s.receivedMs > 5000) return null
        val t = s.t
        val v2 = t.v2
        val fixOk = if (v2 != null) v2.gnssFixOk && !v2.invalidLlh else t.fixType in 2..4
        if (!fixOk || (t.latE7 == 0 && t.lonE7 == 0)) return null
        // Telemetry has no height; 0 m is sent (casters use GGA lat/lon to pick the base / build the VRS).
        return GgaPosition(t.latE7 * 1e-7, t.lonE7 * 1e-7, Gga.quality(true, t.carrSoln, v2?.diffSoln == true), t.numSv, 0.0)
    }
}
