package org.avoperformance.horse.cloud

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.license.LicenseFeature
import org.avoperformance.horse.core.live.LiveAction
import org.avoperformance.horse.core.live.LiveRecorder
import org.avoperformance.horse.license.LicenseGate

/**
 * LIVE desde el servidor: sube a Firebase (`live/{mi código}/{sesión}`) la `TELEMETRY` que llega del pecho en cuanto el
 * pecho está encendido y conectado (en espera, 1 Hz) y mientras graba en la geocerca (2 Hz), para verla en directo en el
 * iPad (pantalla LIVE). Formato y reglas: docs/LIVE_SERVIDOR.md.
 *
 * - Solo con «Compartir en directo» activado, tarjeta AVO personal y licencia con COMPARTIR.
 * - Lo ven mi propia cuenta (mi iPad con mi tarjeta) y los usuarios que aceptaron mis envíos (grants ACCEPTED).
 * - No toca el enlace con el pecho ni el RTCM: solo lee la telemetría que ya llega.
 */
class LiveShare(private val c: AppContainer) {
    data class Status(val sessionId: String? = null, val sent: Long = 0, val error: String? = null)

    private val _status = MutableStateFlow(Status())
    val status: StateFlow<Status> = _status

    private val recorder = LiveRecorder()
    private val queue = Channel<List<LiveAction>>(Channel.UNLIMITED)
    @Volatile private var owner: String? = null
    private var pendingStart: LiveAction.Start? = null
    private var lastStartTryMs = 0L
    @Volatile private var online = false
    private var sent = 0L

    init {
        c.scope.launch(Dispatchers.IO) { for (batch in queue) runCatching { apply(batch) }.onFailure { e -> report(e) } }
        c.scope.launch { c.share.firebase.connected().collect { online = it } }
        // presencia: si el pecho deja de mandar TELEMETRY 60 s (apagado o fuera de alcance), el directo se cierra
        c.scope.launch { while (true) { delay(5_000); tick() } }
    }

    private fun enabled(): Boolean = c.settings.liveShareEnabled && c.identity.card.value != null &&
        LicenseGate.allows(LicenseFeature.COMPARTIR)

    @Synchronized
    private fun tick() {
        val actions = recorder.onTick(System.currentTimeMillis())
        if (actions.isNotEmpty()) queue.trySend(actions)
    }

    /** Cada TELEMETRY del pecho (2 Hz), en el hilo de quien la recibe. */
    @Synchronized
    fun onTelemetry(t: Telemetry, receivedMs: Long) {
        val actions = if (enabled()) recorder.onTelemetry(t, receivedMs) else recorder.finish()
        if (actions.isNotEmpty()) queue.trySend(actions)
    }

    private suspend fun apply(batch: List<LiveAction>) {
        val fb = c.share.firebase
        for (a in batch) {
            if (a is LiveAction.Start) { owner = null; pendingStart = a; lastStartTryMs = 0L }
            // el inicio (entrar en Firebase y escribir la ficha) se reintenta en cada lote hasta que sale bien
            pendingStart?.let { st ->
                val card = c.identity.card.value ?: return
                if (System.currentTimeMillis() - lastStartTryMs < START_RETRY_MS) return   // sin conexión: cada 10 s
                lastStartTryMs = System.currentTimeMillis()
                try {
                    fb.signIn(card)
                    cleanup(card.code, st.sid)
                    writeMeta(card.code, st)
                    owner = card.code; pendingStart = null
                    _status.value = Status(st.sid, sent, null)
                    c.log.i("LIVE", "directo ${st.sid} iniciado")
                } catch (e: Exception) { report(e); return }
            }
            if (a is LiveAction.Start) continue
            val me = owner ?: continue
            val base = "live/$me/${a.sid}"
            val now = System.currentTimeMillis()
            when (a) {
                // la última muestra solo con conexión: sin ella, el iPad recupera el recorrido de los bloques
                is LiveAction.Last -> if (online) { fb.livePut("$base/last", a.line); sent++ }
                is LiveAction.Chunk -> { fb.livePut("$base/s/${a.index}", a.line); fb.livePut("$base/meta/updatedMs", now) }
                is LiveAction.State -> fb.liveUpdate("$base/meta", mapOf("state" to a.state, "updatedMs" to now))
                is LiveAction.End -> {
                    fb.liveUpdate("$base/meta", mapOf("state" to "END", "updatedMs" to now))
                    c.log.i("LIVE", "directo ${a.sid} terminado")
                }
                is LiveAction.Start -> {}
            }
        }
        _status.value = _status.value.copy(sent = sent, error = null)
    }

    private suspend fun writeMeta(me: String, a: LiveAction.Start) {
        val horse = c.db.horses().byId(c.settings.selectedHorseId)
        val rider = c.db.riders().byId(c.settings.selectedRiderId)
        c.share.firebase.livePut("live/$me/${a.sid}/meta", mapOf(
            "horseName" to (horse?.name ?: "").take(120),
            "riderName" to (rider?.name ?: "").take(120),
            "breed" to (horse?.breed ?: "").take(40),
            "startMs" to a.startMs,
            "state" to "REC",
            "updatedMs" to System.currentTimeMillis(),
            "expiresMs" to a.startMs + EXPIRES_MS,
        ))
    }

    /** Borra mis sesiones en directo caducadas (no hay funciones en el servidor: lo hace el propio móvil). */
    private suspend fun cleanup(me: String, keep: String) {
        val now = System.currentTimeMillis()
        runCatching { c.share.firebase.liveSessions(me) }.getOrDefault(emptyList())
            .filter { (sid, exp) -> sid != keep && exp < now }
            .forEach { (sid, _) -> runCatching { c.share.firebase.liveRemove(me, sid) } }
    }

    private fun report(e: Throwable) {
        _status.value = _status.value.copy(error = e.message ?: e.javaClass.simpleName)
        c.log.w("LIVE", "error: ${e.message}")
    }

    companion object {
        /** Una sesión en directo se conserva 24 h desde su inicio (la regla admite hasta 48 h). */
        const val EXPIRES_MS = 24 * 3600_000L
        private const val START_RETRY_MS = 10_000L
    }
}
