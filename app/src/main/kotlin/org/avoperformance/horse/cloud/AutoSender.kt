package org.avoperformance.horse.cloud

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.share.TrainingShare

/**
 * Automatic sending of NEW trainings to a selected AVO user (Firebase). It sends each training once,
 * as soon as it is downloaded and verified against the watch. Only trainings recorded after enabling
 * the option are sent (older ones are never sent in bulk). If the network fails, it retries on the next
 * connection or download. Trainings without a horse and rider are left pending until they get them.
 */
class AutoSender(private val c: AppContainer) {
    private val lock = Mutex()
    private val _status = MutableStateFlow<String?>(null)
    val status: StateFlow<String?> = _status

    fun trigger(reason: String) {
        c.scope.launch { runCatching { run(reason) }.onFailure { c.log.w("AUTOSEND", "${it.message}") } }
    }

    private suspend fun run(reason: String) = lock.withLock {
        val s = c.settings
        val to = s.autoSendTo ?: return
        val me = c.identity.card.value ?: run { _status.value = "Sin identidad AVO (tarjeta NFC)"; return }
        if (to == me.code) return
        val sent = s.autoSendDone
        val horses = c.db.horses().all().first()
        val riders = c.db.riders().all().first()
        val pending = c.db.trainings().all().first().filter {
            it.startRtcMs >= s.autoSendSinceMs && it.sessionId !in sent && it.localDir != null &&
                it.localSha256 != null && it.localSha256 == it.watchSha256 &&
                it.state != SyncState.ERROR_INTEGRIDAD.name
        }.sortedBy { it.startRtcMs }
        if (pending.isEmpty()) { _status.value = "Al día · ${s.autoSendName}"; return }
        for (t in pending) {
            val horse = horses.firstOrNull { it.code == t.horseCode }?.name.orEmpty()
            val rider = riders.firstOrNull { it.code == t.riderCode }?.name.orEmpty()
            if (horse.isBlank() || rider.isBlank()) { _status.value = "${t.sessionId}: falta caballo o jinete (pendiente)"; continue }
            _status.value = "Enviando ${t.sessionId} a ${s.autoSendName}…"
            val file = TrainingShare.buildPackage(c.app, t, horse, rider)
            try {
                c.cloud.send(me, to, t.sessionId, file) { i, n -> _status.value = "Enviando ${t.sessionId} a ${s.autoSendName}: $i/$n" }
                s.autoSendDone = s.autoSendDone + t.sessionId
                c.log.i("AUTOSEND", "${t.sessionId} → $to ($reason)")
                _status.value = "Último enviado: ${t.sessionId} → ${s.autoSendName}"
            } catch (e: Exception) {
                _status.value = "Sin enviar (${e.message}). Se reintentará."
                return
            } finally { file.delete() }
        }
    }
}
