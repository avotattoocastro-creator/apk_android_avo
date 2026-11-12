package org.avoperformance.horse.core.telemetry

/**
 * Age of the last RTCM message the receiver actually used, measured from the "RTCM used" counter of the back unit
 * (telemetry v2 `rtcmUsedByReceiver`). Needed because some ZED-F9P firmware leaves NAV-PVT lastCorrectionAge at 0
 * ("not available") even while it applies corrections: seen in field on 02/11/2026 with 4139 messages used.
 *
 * Resolution is the telemetry period (~0.5 s). Returns null until the counter has been seen to increase once.
 */
class RtcmUseTracker {
    private var lastCount = -1L
    private var lastIncreaseMs = -1L

    /** [count] = messages used by the receiver so far; [atMs] = when that telemetry arrived. */
    fun update(count: Long, atMs: Long) {
        if (lastCount >= 0 && count > lastCount) lastIncreaseMs = atMs
        if (count < lastCount) lastIncreaseMs = -1L   // back unit restarted: counter went back to 0
        lastCount = count
    }

    fun ageMs(nowMs: Long): Long? = if (lastIncreaseMs < 0) null else (nowMs - lastIncreaseMs).coerceAtLeast(0L)

    fun reset() { lastCount = -1L; lastIncreaseMs = -1L }
}
