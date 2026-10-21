package org.avoperformance.horse.dnd

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.core.ble.GeofenceState
import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.data.Settings

/**
 * Optional, session-confirmed Do Not Disturb (DND).
 *
 * The phone never evaluates raw GPS coordinates to change DND. The watch already
 * performs geofence confirmation/hysteresis. Telemetry is its authoritative state.
 * Manual training and stale or disconnected telemetry cannot activate DND.
 *
 * Android 15+ (target API 35) toggles an application-owned implicit Zen rule;
 * invoking ALL disables our own rule and does not disable the user's DND rules.
 * Android 10–14 modifies the global mode: restore only when AVO's expected
 * interruption filter is still active, to respect a manual user override.
 */
class GeofenceDndController(
    context: Context,
    private val settings: Settings,
    private val log: AppLog,
) {
    private val p = context.getSharedPreferences("avo_geofence_dnd", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val priority = NotificationManager.INTERRUPTION_FILTER_PRIORITY
    private val all = NotificationManager.INTERRUPTION_FILTER_ALL
    private val ttlMs = 12L * 60 * 60 * 1000

    fun hasPolicyAccess(): Boolean =
        runCatching { manager?.isNotificationPolicyAccessGranted == true }.getOrDefault(false)

    @Synchronized
    fun onWatchTelemetry(t: Telemetry?, receivedMs: Long, connected: Boolean) {
        if (t == null || !connected || System.currentTimeMillis() - receivedMs !in 0..5000L) return

        // On the V3.4.4+ telemetry we can positively exclude manual sessions.
        // Earlier firmware is allowed only when its geofence state says RECORDING.
        val automatic = when (t.geofence) {
            GeofenceState.RECORDING, GeofenceState.EXIT_PENDING,
            GeofenceState.POST_RECORDING, GeofenceState.PAUSED -> true
            else -> false
        } && t.v2?.manualSession != true

        val recording = t.session == WatchSessionState.RECORDING ||
            t.session == WatchSessionState.PAUSED
        if (settings.autoDndGeofence && recording && automatic) activate()
        else restoreOwned("sin grabación automática confirmada")
    }

    /** Optional last-resort recovery after a process died during a past training. */
    @Synchronized
    fun restoreExpired() {
        if (p.getBoolean("owned", false)) {
            val age = System.currentTimeMillis() - p.getLong("started_at", 0L)
            if (age < 0 || age > ttlMs || !settings.autoDndGeofence) {
                restoreOwned("recuperación de estado anterior")
            }
        }
    }

    @Synchronized
    private fun activate() {
        if (p.getBoolean("owned", false) || !hasPolicyAccess()) return
        val current = runCatching { manager.currentInterruptionFilter }.getOrDefault(-1)
        // If the user has already enabled a DND rule, leave it untouched.
        if (current != all) return
        // Persist before writing the OS state so we can undo after process death.
        if (!p.edit().putBoolean("owned", true).putInt("previous", current)
                .putLong("started_at", System.currentTimeMillis()).commit()) {
            log.w("DND", "No se pudo guardar el estado previo; no se activa DND")
            return
        }
        val ok = runCatching { manager.setInterruptionFilter(priority) }
        if (ok.isFailure) {
            p.edit().clear().commit()
            log.w("DND", "No molestar no autorizado por Android")
        } else {
            log.i("DND", "No molestar de AVO activado para sesión automática")
        }
    }

    @Synchronized
    fun restoreOwned(reason: String) {
        if (!p.getBoolean("owned", false)) return
        if (!hasPolicyAccess()) {
            // Android revoking policy access also removes/rejects this app's rule.
            log.w("DND", "Sin acceso a política de notificaciones; comprobar DND manualmente")
            return
        }
        val previous = p.getInt("previous", all)
        val current = runCatching { manager.currentInterruptionFilter }.getOrDefault(-1)
        val modern = Build.VERSION.SDK_INT >= 35
        // On Android 15+ ALL deactivates only our own rule.
        // On older systems do not overwrite a DND mode the user changed.
        if (modern || current == priority) {
            val result = runCatching { manager.setInterruptionFilter(previous) }
            if (result.isFailure) {
                log.w("DND", "No se pudo restaurar el estado: " + result.exceptionOrNull()?.message)
                return
            }
        }
        p.edit().clear().commit()
        log.i("DND", "Modo previo conservado/restaurado: " + reason)
    }
}
