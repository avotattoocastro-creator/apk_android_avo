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

    fun start() {
        if (client != null) return
        val cfg = settings.ntripConfig()
        val problems = cfg.problems()
        if (problems.isNotEmpty()) { _state.value = NtripState.Failed(problems.joinToString("; ")); return }
        watch.rtcmAckListener = { a ->
            synchronized(pacer) { pacer.onAck(a.freeBytes, a.expectedSeq, a.droppedBytes, System.currentTimeMillis()) }
            lastFree = a.freeBytes
        }
        val c = NtripClient(cfg, ::ggaPosition,
            onData = { b, o, n ->
                val frames = synchronized(framer) { framer.feed(b, o, n) }
                val now = System.currentTimeMillis()
                synchronized(pacer) { frames.forEach { pacer.offer(it, now) } }
            },
            onState = { _state.value = it; log.i("NTRIP", it.texto) },
            onStats = { _stats.value = it })
        client = c
        thread(name = "avo-ntrip", isDaemon = true) { c.run(); if (client === c) client = null }
        sender = scope.launch(Dispatchers.IO) { sendLoop() }
    }

    fun stop() {
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
