package org.avoperformance.horse.core.telemetry

/**
 * 2.14-gnss: where the GNSS data stops, stage by stage, from counters that already exist (no protocol change).
 *
 *  - RTCM: caster → phone (NTRIP client) → watch (BLE, DIAG `rtcm_in`) → back (ESP-NOW, `rtcm_out` / `back_rtcm_rx`)
 *    → ZED-F9P UART (`back_rtcm_zed`) → used by the receiver (`zed_used`, from UBX-RXM-RTCM).
 *  - UBX: valid UBX frames the back received from the receiver (`ubx`).
 *
 * The DIAG_GET text of the watch (CHEST ≥ 3.5.0, back block when a BackStatus has arrived) carries the counters; two
 * snapshots a few seconds apart give the rates. A counter that does not move while the previous stage moves is where
 * the chain breaks. "NTRIP connected" is never presented as "RTK working": only `zed_used` going up says the
 * receiver applies the corrections, and only NAV-PVT carrSoln says FLOAT/FIX.
 */
data class GnssDiagSnapshot(
    val atMs: Long,
    val casterBytes: Long?, val phoneSentBytes: Long?,
    val watchRtcmIn: Long?, val watchRtcmOut: Long?, val watchRtcmDrop: Long?,
    val backRtcmRx: Long?, val backRtcmToZed: Long?, val backRtcmFramesBad: Long?, val backRtcmGap: Long?, val backRtcmNotWritten: Long?,
    val zedUsed: Long?, val zedFailed: Long?,
    val ubxFrames: Long?, val zedState: String?, val zedBaud: Long?, val backStatusAgeMs: Long?,
) {
    companion object {
        private fun n(m: Map<String, String>, k: String): Long? = m[k]?.trim()?.toLongOrNull()?.takeIf { it >= 0 }

        /** [diag] = DiagParser.parse(DIAG_GET text); [casterBytes] / [phoneSentBytes] = the phone's own NTRIP counters. */
        fun from(diag: Map<String, String>, atMs: Long, casterBytes: Long?, phoneSentBytes: Long?): GnssDiagSnapshot {
            val backAge = n(diag, "back_status_age_ms")?.takeIf { it != 0xFFFFFFFFL }
            return GnssDiagSnapshot(
                atMs, casterBytes, phoneSentBytes,
                n(diag, "rtcm_in"), n(diag, "rtcm_out"), n(diag, "rtcm_drop"),
                n(diag, "back_rtcm_rx"), n(diag, "back_rtcm_zed"), n(diag, "back_rtcm_bad"), n(diag, "back_rtcm_gap"), n(diag, "back_rtcm_nowr"),
                n(diag, "zed_used"), n(diag, "zed_fail"),
                n(diag, "ubx"), diag["zed"]?.takeIf { it.isNotBlank() && it != "?" }, n(diag, "zed_baud"), backAge,
            )
        }
    }
}

enum class StageState { OK, PARADO, ERROR, SIN_DATOS }

data class ChainStage(val name: String, val value: String?, val state: StageState)

data class GnssChainReport(val rtcm: List<ChainStage>, val rtcmVerdict: String, val rtcmVerdictState: StageState, val ubx: ChainStage)

object GnssChain {
    /** A BackStatus older than this inside the watch means the back counters in DIAG are not current. */
    const val BACK_STALE_MS = 5_000L

    private fun rate(prev: Long?, cur: Long?, dtMs: Long): Double? {
        if (prev == null || cur == null || dtMs <= 0) return null
        val d = cur - prev
        return if (d < 0) null else d * 1000.0 / dtMs     // counter went back: the unit restarted
    }

    private fun bytes(v: Long): String = when {
        v >= 1_048_576 -> String.format(java.util.Locale.US, "%.1f MB", v / 1_048_576.0)
        v >= 1024 -> String.format(java.util.Locale.US, "%.1f kB", v / 1024.0)
        else -> "$v B"
    }

    private fun stage(name: String, prev: Long?, cur: Long?, dtMs: Long, unit: String, isBytes: Boolean, upstreamMoving: Boolean): ChainStage {
        if (cur == null) return ChainStage(name, null, StageState.SIN_DATOS)
        val total = if (isBytes) bytes(cur) else "$cur"
        val r = rate(prev, cur, dtMs) ?: return ChainStage(name, total, if (cur > 0) StageState.OK else StageState.SIN_DATOS)
        val rs = if (r >= 10) String.format(java.util.Locale.US, "%.0f %s", r, unit) else String.format(java.util.Locale.US, "%.1f %s", r, unit)
        return when {
            r > 0 -> ChainStage(name, "$rs · total $total", StageState.OK)
            upstreamMoving -> ChainStage(name, "parado · total $total", StageState.PARADO)
            else -> ChainStage(name, "sin tráfico · total $total", StageState.SIN_DATOS)
        }
    }

    fun report(prev: GnssDiagSnapshot?, cur: GnssDiagSnapshot?, ntripStreaming: Boolean): GnssChainReport? {
        if (cur == null) return null
        val dt = if (prev != null) cur.atMs - prev.atMs else 0L
        val backFresh = cur.backStatusAgeMs != null && cur.backStatusAgeMs <= BACK_STALE_MS
        fun mov(p: Long?, c: Long?) = (rate(p, c, dt) ?: 0.0) > 0.0
        val caster = stage("Caster → móvil", prev?.casterBytes, cur.casterBytes, dt, "B/s", true, ntripStreaming)
        val phone = stage("Móvil → reloj", prev?.phoneSentBytes, cur.phoneSentBytes, dt, "B/s", true, mov(prev?.casterBytes, cur.casterBytes))
        val watchIn = stage("Recibido en el reloj", prev?.watchRtcmIn, cur.watchRtcmIn, dt, "B/s", true, mov(prev?.phoneSentBytes, cur.phoneSentBytes))
        val watchOut = stage("Reloj → espalda", prev?.watchRtcmOut, cur.watchRtcmOut, dt, "B/s", true, mov(prev?.watchRtcmIn, cur.watchRtcmIn))
        val b = if (backFresh) cur else null
        val bp = if (backFresh) prev else null
        val backRx = stage("Recibido en la espalda", bp?.backRtcmRx, b?.backRtcmRx, dt, "B/s", true, mov(prev?.watchRtcmOut, cur.watchRtcmOut))
        val toZed = stage("Espalda → receptor (UART)", bp?.backRtcmToZed, b?.backRtcmToZed, dt, "B/s", true, mov(bp?.backRtcmRx, b?.backRtcmRx))
        val used = stage("Usadas por el receptor", bp?.zedUsed, b?.zedUsed, dt, "msg/s", false, mov(bp?.backRtcmToZed, b?.backRtcmToZed))
        val stages = mutableListOf(caster, phone, watchIn, watchOut, backRx, toZed, used)

        // Losses and rejections on the way (only when they grow).
        val errs = mutableListOf<String>()
        if (mov(prev?.watchRtcmDrop, cur.watchRtcmDrop)) errs += "el reloj descarta RTCM"
        if (mov(bp?.backRtcmFramesBad, b?.backRtcmFramesBad)) errs += "tramas RTCM con CRC erróneo en la espalda"
        if (mov(bp?.backRtcmGap, b?.backRtcmGap)) errs += "huecos en la radio reloj → espalda"
        if (mov(bp?.backRtcmNotWritten, b?.backRtcmNotWritten)) errs += "la espalda no puede escribir al receptor (baudios sin detectar)"
        if (mov(bp?.zedFailed, b?.zedFailed)) errs += "el receptor rechaza mensajes RTCM"
        if (errs.isNotEmpty()) stages += ChainStage("Pérdidas", errs.joinToString("; "), StageState.ERROR)

        val firstStop = stages.take(7).firstOrNull { it.state == StageState.PARADO }
        val (verdict, vstate) = when {
            !ntripStreaming && caster.state != StageState.OK -> "NTRIP sin datos: no hay correcciones que transportar" to StageState.SIN_DATOS
            !backFresh -> "Sin estado reciente de la espalda: no se puede saber si las correcciones llegan al receptor" to StageState.SIN_DATOS
            firstStop != null -> "Las correcciones se detienen en «${firstStop.name}»" to StageState.PARADO
            used.state == StageState.OK -> "El receptor está usando las correcciones (no implica RTK FIX)" to StageState.OK
            prev == null -> "Midiendo el caudal…" to StageState.SIN_DATOS
            else -> "Correcciones sin uso confirmado por el receptor" to StageState.PARADO
        }

        val ubx = when {
            !backFresh || cur.ubxFrames == null -> ChainStage("Recepción UBX (espalda)", null, StageState.SIN_DATOS)
            else -> {
                val r = rate(bp?.ubxFrames, b?.ubxFrames, dt)
                val extra = listOfNotNull(cur.zedState?.lowercase()?.replace('_', ' '), cur.zedBaud?.let { "$it baudios" }).joinToString(" · ")
                when {
                    r == null -> ChainStage("Recepción UBX (espalda)", "${cur.ubxFrames} tramas" + if (extra.isNotEmpty()) " · $extra" else "", StageState.OK)
                    r > 0 -> ChainStage("Recepción UBX (espalda)", String.format(java.util.Locale.US, "%.1f tramas/s", r) + if (extra.isNotEmpty()) " · $extra" else "", StageState.OK)
                    else -> ChainStage("Recepción UBX (espalda)", "parada" + if (extra.isNotEmpty()) " · $extra" else "", StageState.PARADO)
                }
            }
        }
        return GnssChainReport(stages, verdict, vstate, ubx)
    }

    /** Engineering target for the speed: NAV-PVT sAcc below 0.20 km/h (55.6 mm/s). */
    const val SPEED_ACC_TARGET_MM_S = 55L
    fun speedTargetMet(sAccMmS: Long): Boolean = sAccMmS in 1..SPEED_ACC_TARGET_MM_S
}
