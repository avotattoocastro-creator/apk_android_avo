package org.avoperformance.horse.share

import kotlinx.coroutines.flow.first
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.cloud.CloudSync
import org.avoperformance.horse.data.HorseEntity
import org.avoperformance.horse.data.RiderEntity
import org.avoperformance.horse.data.TrainingEntity

/**
 * Asignar caballo y jinete a un entrenamiento (AVO-ASSIGN-1) desde cualquier sitio de la app: el diálogo «Caballo y
 * jinete», la confirmación tras la descarga y los cambios que llegan de la Nube AVO (iPad o Windows).
 * Busca la ficha por código y luego por nombre; si no existe, la crea. Guarda cuándo se asignó para que, entre apps,
 * gane la asignación más reciente (docs/NUBE_SESIONES.md).
 */
object TrainingAssign {
    suspend fun assign(
        c: AppContainer, sessionId: String, horseName: String, riderName: String,
        horseCode: String? = null, riderCode: String? = null, atMs: Long = System.currentTimeMillis(), pushToCloud: Boolean = true,
    ): TrainingEntity {
        val h = horseName.trim(); val r = riderName.trim()
        require(h.isNotEmpty() && r.isNotEmpty()) { "Faltan el caballo o el jinete" }
        val horses = c.db.horses().all().first()
        val riders = c.db.riders().all().first()
        val eh = horses.firstOrNull { !horseCode.isNullOrBlank() && it.code == horseCode } ?: horses.firstOrNull { it.name.equals(h, true) }
        val er = riders.firstOrNull { !riderCode.isNullOrBlank() && it.code == riderCode } ?: riders.firstOrNull { it.name.equals(r, true) }
        val hc = eh?.code ?: horseCode?.takeIf { it.isNotBlank() } ?: ("H_" + java.util.UUID.randomUUID().toString().take(16))
        val rc = er?.code ?: riderCode?.takeIf { it.isNotBlank() } ?: ("R_" + java.util.UUID.randomUUID().toString().take(16))
        if (eh == null) c.db.horses().insert(HorseEntity(code = hc, name = h))
        if (er == null) c.db.riders().insert(RiderEntity(code = rc, name = r))
        val current = c.db.trainings().byId(sessionId) ?: error("Entrenamiento no encontrado")
        val linked = current.copy(horseCode = hc, riderCode = rc, updatedMs = System.currentTimeMillis())
        c.db.trainings().upsert(linked)
        markAssigned(c, sessionId, atMs)
        markConfirmed(c, sessionId)
        if (pushToCloud) c.share.runNow()
        return linked
    }

    fun assignedMs(c: AppContainer, sessionId: String): Long = CloudSync.decode(c.settings.cloudAssigned)[sessionId]?.toLongOrNull() ?: 0L

    @Synchronized fun markAssigned(c: AppContainer, sessionId: String, ms: Long) {
        val m = CloudSync.decode(c.settings.cloudAssigned).toMutableMap()
        m[sessionId] = ms.toString()
        c.settings.cloudAssigned = CloudSync.encode(m)
    }

    // ------------------------------------------------------------- confirmación tras la descarga

    private fun confirmedSet(c: AppContainer): Set<String>? = c.settings.assignConfirmed?.lineSequence()?.filter { it.isNotBlank() }?.toSet()

    @Synchronized fun markConfirmed(c: AppContainer, sessionId: String) {
        val s = (confirmedSet(c) ?: emptySet()) + sessionId
        c.settings.assignConfirmed = s.joinToString("\n")
    }

    /**
     * Entrenamientos descargados y verificados con el reloj que aún no se han confirmado (el más reciente primero).
     * La primera vez (al instalar la 2.12) da por confirmados todos los que ya había: solo se pregunta por los nuevos.
     */
    @Synchronized fun pendingConfirmation(c: AppContainer, all: List<TrainingEntity>): List<TrainingEntity> {
        val verified = all.filter { it.watchState != "IMPORTADO" && it.localSha256 != null && it.localSha256.equals(it.watchSha256, true) }
        val done = confirmedSet(c)
        if (done == null) { c.settings.assignConfirmed = verified.joinToString("\n") { it.sessionId }; return emptyList() }
        return verified.filter { it.sessionId !in done }.sortedByDescending { it.startRtcMs }
    }
}
