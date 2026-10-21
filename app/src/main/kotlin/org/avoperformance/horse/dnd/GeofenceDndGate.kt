package org.avoperformance.horse.dnd

import org.avoperformance.horse.core.ble.GeofenceState
import org.avoperformance.horse.core.ble.WatchSessionState

/** Pure decisions shared by the Android controller and repeatable JVM tests. */
internal object GeofenceDndGate {
    fun isFresh(receivedMs: Long, nowMs: Long): Boolean =
        receivedMs > 0 && nowMs - receivedMs in 0L..5000L

    fun shouldSilence(
        session: WatchSessionState,
        fence: GeofenceState,
        manualSession: Boolean?,
    ): Boolean {
        if (manualSession == true) return false
        if (session != WatchSessionState.RECORDING && session != WatchSessionState.PAUSED) return false
        return when (fence) {
            GeofenceState.RECORDING,
            GeofenceState.EXIT_PENDING,
            GeofenceState.POST_RECORDING,
            GeofenceState.PAUSED -> true
            else -> false
        }
    }
}
