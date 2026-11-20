package org.avoperformance.horse.core.cloud

import java.security.MessageDigest

/**
 * Nube AVO (Cloud Storage for Firebase): copia de los entrenamientos del usuario.
 * Contrato (el mismo en Android, iPad y Windows; ver docs/NUBE_SESIONES.md y firebase/storage.rules):
 *  - Ruta: `trainings/<CODIGO_TARJETA>/<archivo>.avo`, un paquete AVO-TRAINING-1 por entrenamiento.
 *  - Metadatos propios: `sha256` (del .avo, obligatorio), `fp` (huella de lo que hay en el paquete), `sessionId`,
 *    `horseCode`, `horseName`, `riderCode`, `riderName`, `assignedMs` (cuándo se eligió el caballo/jinete; 0 = nunca a mano),
 *    `startRtcMs`, `distanceM`, `app`.
 *  - Cualquier app puede cambiar el caballo/jinete y volver a subir el .avo: **gana la asignación más reciente**
 *    (`assignedMs`), la misma regla que AVO-ASSIGN-1 al importar.
 */
object CloudSync {
    const val PREFIX = "trainings"
    const val MAX_BYTES: Long = 40L * 1024 * 1024

    /** Nombre del archivo en la nube (mismo criterio que el .avo de WhatsApp: `AVO_<id>.avo`, solo caracteres seguros). */
    fun fileName(sessionId: String): String =
        "AVO_" + sessionId.replace(Regex("[^A-Za-z0-9_-]"), "_").take(130) + ".avo"

    fun path(cardCode: String, sessionId: String): String = "$PREFIX/${cardCode.uppercase()}/${fileName(sessionId)}"

    /**
     * Huella de lo que irá en el paquete: si no cambia, no hace falta volver a subirlo (el .avo es un ZIP con fecha y
     * su SHA-256 cambia en cada empaquetado). Cambia al reasignar caballo o jinete.
     */
    fun fingerprint(localSha256: String, horseCode: String?, riderCode: String?, horseName: String, riderName: String): String {
        val d = MessageDigest.getInstance("SHA-256")
        d.update(listOf(localSha256.lowercase(), horseCode.orEmpty(), riderCode.orEmpty(), horseName, riderName).joinToString("\u001f").toByteArray())
        return d.digest().take(16).joinToString("") { "%02x".format(it) }
    }

    data class Candidate(val sessionId: String, val fingerprint: String, val startRtcMs: Long)

    /** Lo que falta por subir (lo más reciente primero), comparando con las huellas ya subidas. */
    fun pending(candidates: List<Candidate>, uploaded: Map<String, String>): List<Candidate> =
        candidates.filter { uploaded[it.sessionId] != it.fingerprint }.sortedByDescending { it.startRtcMs }

    /** Lectura/escritura del registro local de huellas subidas (`id\tfp` por línea). */
    fun encode(m: Map<String, String>): String = m.entries.sortedBy { it.key }.joinToString("\n") { "${it.key}\t${it.value}" }
    fun decode(s: String?): Map<String, String> = s.orEmpty().lineSequence().mapNotNull { l ->
        val i = l.indexOf('\t'); if (i <= 0) null else l.substring(0, i) to l.substring(i + 1)
    }.toMap()

    /** Lo que dicen los metadatos de la nube de un entrenamiento. */
    data class Remote(
        val fingerprint: String?, val assignedMs: Long,
        val horseCode: String?, val horseName: String?, val riderCode: String?, val riderName: String?,
    ) {
        val hasIdentity: Boolean get() = !horseName.isNullOrBlank() && !riderName.isNullOrBlank()
    }

    enum class Action { UPLOAD, APPLY_REMOTE, NOTHING }

    /**
     * Qué hacer con un entrenamiento local frente a su copia en la nube.
     * [localFp] es null si en este dispositivo aún no tiene caballo y jinete (no se puede subir).
     * [localHorse]/[localRider] son los nombres actuales aquí (para no aplicar lo que ya coincide).
     */
    fun decide(localFp: String?, localAssignedMs: Long, localHorse: String?, localRider: String?, remote: Remote?): Action = when {
        remote == null -> if (localFp != null) Action.UPLOAD else Action.NOTHING
        remote.fingerprint != null && remote.fingerprint == localFp -> Action.NOTHING
        // ya dice lo mismo (aunque la huella la calculara otra app con otros códigos): no se vuelve a subir
        remote.hasIdentity && same(remote.horseName, localHorse) && same(remote.riderName, localRider) -> Action.NOTHING
        remote.hasIdentity && (localFp == null || remote.assignedMs > localAssignedMs) -> Action.APPLY_REMOTE
        localFp != null && localAssignedMs >= remote.assignedMs -> Action.UPLOAD
        else -> Action.NOTHING
    }

    private fun same(a: String?, b: String?) = a.orEmpty().trim().equals(b.orEmpty().trim(), ignoreCase = true)
}
