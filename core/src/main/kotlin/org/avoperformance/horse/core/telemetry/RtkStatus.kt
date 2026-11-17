package org.avoperformance.horse.core.telemetry

import org.avoperformance.horse.core.ble.SessionCmd
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.ble.correctionAgeMaxMs

/** RTK state as reported by the receiver (ZED-F9P NAV-PVT via the watch). Never inferred from NTRIP alone. */
enum class RtkState(val texto: String) {
    DESCONOCIDO("Sin datos del reloj"),
    SIN_GNSS("Sin GNSS"),
    AUTONOMO("GNSS autónomo"),
    DGNSS("DGNSS"),
    FLOAT("RTK FLOAT"),
    FIX("RTK FIX"),
}

data class RtkView(
    val state: RtkState,
    val satellites: Int?,
    val hAccM: Double?,
    val vAccM: Double?,
    /** Upper bound of the correction age in ms (receiver gives a range code), null when not available. */
    val correctionAgeMaxMs: Long?,
    val gnssAgeMs: Long?,
    val telemetryAgeMs: Long,
)

object RtkDeriver {
    /** Telemetry older than this is shown as unknown (the watch sends 2 Hz). */
    const val TELEMETRY_STALE_MS = 3000L
    /** GNSS sample older than this means the back unit stopped sending. */
    const val GNSS_STALE_MS = 3000L

    fun derive(t: Telemetry?, telemetryAgeMs: Long): RtkView {
        if (t == null || telemetryAgeMs > TELEMETRY_STALE_MS) return RtkView(RtkState.DESCONOCIDO, null, null, null, null, null, telemetryAgeMs)
        val v2 = t.v2
        val gnssAge = v2?.gnssAgeMs
        val noGnss = when {
            v2 != null -> !v2.haveGnss || gnssAge == null || gnssAge > GNSS_STALE_MS || !v2.gnssFixOk || v2.invalidLlh
            else -> t.fixType == 0 || t.fixType == 5   // v1: only fixType is available
        } || t.fixType == 0
        val state = when {
            noGnss -> RtkState.SIN_GNSS
            t.carrSoln == 2 -> RtkState.FIX
            t.carrSoln == 1 -> RtkState.FLOAT
            v2?.diffSoln == true -> RtkState.DGNSS
            else -> RtkState.AUTONOMO
        }
        return RtkView(
            state,
            if (noGnss && v2 != null && !v2.haveGnss) null else t.numSv,
            if (noGnss) null else t.hAccMm / 1000.0,
            if (noGnss || v2 == null) null else v2.vAccMm / 1000.0,
            v2?.let { correctionAgeMaxMs(it.corrAgeCode) },
            gnssAge,
            telemetryAgeMs,
        )
    }
}

/**
 * Prevents duplicated session commands and only reports "confirmed" when the
 * watch both accepted the command (BLE status OK/DUPLICATE) and its telemetry
 * shows the expected state.
 */
class SessionCommandTracker(private val confirmTimeoutMs: Long = 6000) {
    sealed class State {
        object Idle : State()
        data class Sending(val cmd: SessionCmd, val sinceMs: Long) : State()
        data class WaitingTelemetry(val cmd: SessionCmd, val sinceMs: Long) : State()
        data class Confirmed(val cmd: SessionCmd, val atMs: Long) : State()
        data class Failed(val cmd: SessionCmd, val reason: String) : State()
    }

    var state: State = State.Idle; private set

    fun busy(): Boolean = state is State.Sending || state is State.WaitingTelemetry

    /** Returns false (and does nothing) if a command is already in progress. */
    fun begin(cmd: SessionCmd, nowMs: Long): Boolean {
        if (busy()) return false
        state = State.Sending(cmd, nowMs)
        return true
    }

    fun onResponse(status: BleStatus, nowMs: Long, current: WatchSessionState?) {
        val s = state as? State.Sending ?: return
        when (status) {
            BleStatus.OK, BleStatus.DUPLICATE -> {
                state = if (s.cmd == SessionCmd.MARKER) State.Confirmed(s.cmd, nowMs) else State.WaitingTelemetry(s.cmd, nowMs)
                if (current != null) onTelemetry(current, nowMs)
            }
            BleStatus.BUSY -> state = State.Failed(s.cmd, "El reloj no aceptó la orden en su estado actual")
            BleStatus.NOT_ALLOWED -> state = State.Failed(s.cmd, "Orden no permitida (falta confirmación)")
            BleStatus.AUTH_REQUIRED -> state = State.Failed(s.cmd, "Teléfono no autorizado en el reloj")
            else -> state = State.Failed(s.cmd, "Error: ${status.texto}")
        }
    }

    fun onTransportError(msg: String) {
        val s = state as? State.Sending ?: return
        // Result unknown: the watch may have executed it. Telemetry decides.
        state = State.WaitingTelemetry(s.cmd, System.currentTimeMillis()).also { unknownReason = msg }
    }
    var unknownReason: String? = null; private set

    fun onTelemetry(session: WatchSessionState, nowMs: Long) {
        val s = state as? State.WaitingTelemetry ?: return
        if (expected(s.cmd, session)) state = State.Confirmed(s.cmd, nowMs)
        else if (nowMs - s.sinceMs > confirmTimeoutMs) state = State.Failed(s.cmd, "El reloj no confirmó el cambio de estado (estado actual: ${session.texto})")
    }

    /** Called periodically: fails a pending confirmation when no matching telemetry arrived in time. */
    fun onTick(nowMs: Long) {
        val s = state
        if (s is State.WaitingTelemetry && nowMs - s.sinceMs > confirmTimeoutMs) state = State.Failed(s.cmd, "El reloj no confirmó el cambio de estado a tiempo")
    }

    fun reset() { state = State.Idle; unknownReason = null }

    companion object {
        fun expected(cmd: SessionCmd, s: WatchSessionState): Boolean = when (cmd) {
            SessionCmd.START, SessionCmd.RESUME -> s == WatchSessionState.RECORDING
            SessionCmd.STOP -> s == WatchSessionState.STOPPED_WAITING_UPLOAD || s == WatchSessionState.COMPLETED || s == WatchSessionState.IDLE || s == WatchSessionState.ARMED
            SessionCmd.PAUSE -> s == WatchSessionState.PAUSED
            SessionCmd.REARM -> s == WatchSessionState.ARMED || s == WatchSessionState.IDLE
            SessionCmd.MARKER -> true
        }
    }
}
