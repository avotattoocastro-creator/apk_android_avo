package org.avoperformance.horse.core.sync

import org.avoperformance.horse.core.ble.WatchFileState

/**
 * Deleting trainings from the watch (vest SD card), protected with the password "AVO".
 *
 * The watch keeps its own protection: it never deletes the session being recorded, and without the
 * `force` flag it refuses sessions not marked as uploaded. With the server not configured nothing is ever
 * marked as uploaded, so after the password the app sends `force` = 1.
 *
 * The password only prevents an accidental deletion (it is in the public source code): it is not a security key.
 */
object WatchDelete {
    const val PASSWORD = "AVO"
    /** watchState of a training whose watch copy was deleted from the app (the phone copy is kept). */
    const val DELETED_ON_WATCH = "BORRADO_RELOJ"

    /** Exact "AVO" (spaces around are ignored). */
    fun passwordOk(input: String): Boolean = input.trim() == PASSWORD

    enum class Safety(val texto: String) {
        /** The phone holds a copy verified against the watch (same SHA-256): nothing is lost. */
        COPIA_EN_MOVIL("Guardado y verificado en el móvil: no se pierde nada"),
        /** No verified copy on the phone: the training is lost for good. */
        SE_PIERDE("NO está guardado en el móvil: se perderá para siempre"),
    }

    private val VERIFIED = setOf(SyncState.VERIFICADO_LOCAL, SyncState.PENDIENTE_SERVIDOR, SyncState.SUBIENDO,
        SyncState.VERIFICADO_SERVIDOR, SyncState.MARCADO_EN_RELOJ)

    fun safety(t: LocalTraining): Safety =
        if (t.state in VERIFIED && t.localSha256Hex != null && t.localSha256Hex.equals(t.watchSha256Hex, ignoreCase = true)) Safety.COPIA_EN_MOVIL
        else Safety.SE_PIERDE

    /** The training is (as far as the phone knows) on the watch and is not being recorded. */
    fun canDelete(t: LocalTraining, watchStateText: String): Boolean =
        t.state != SyncState.GRABANDO && t.watchState != WatchFileState.OPEN &&
            watchStateText != DELETED_ON_WATCH && watchStateText != "IMPORTADO"

    /** Trainings that can be removed from the watch without losing anything ("liberar el reloj"). */
    fun freeable(all: List<Pair<LocalTraining, String>>): List<LocalTraining> =
        all.filter { (t, ws) -> canDelete(t, ws) && safety(t) == Safety.COPIA_EN_MOVIL }.map { it.first }
}
