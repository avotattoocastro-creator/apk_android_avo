package org.avoperformance.horse.core.live

import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.ble.WatchSessionState
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * LIVE desde el servidor (Actualizaciones 1 del iPad, 19/11/2026).
 * El Android sube a Firebase (`live/{owner}/{sid}`) lo que recibe del pecho por `TELEMETRY` (2 Hz) y el iPad lo muestra
 * en directo. No cambia ningún contrato binario: es una copia de campos de `TELEMETRY v1–v3` en texto.
 *
 * Formato `LIVE1` (documentado en docs/LIVE_SERVIDOR.md; mismo formato en ipad/AVOiPad/Core/LiveCodec.swift):
 *   muestra  = t_ms,latE7,lonE7,speed_mm_s,dist_cm,fix,carr,hacc_mm,num_sv,session
 *   `last`   = "LIVE1," + muestra
 *   `s/{n}`  = "LIVE1," + muestra(;muestra)*      (bloques de ~10 s)
 * Solo enteros: `t_ms` cuenta desde el inicio de la sesión en directo (reloj del móvil al recibir).
 */
data class LiveSample(
    val tMs: Long, val latE7: Int, val lonE7: Int, val speedMmS: Int, val distCm: Long,
    val fix: Int, val carr: Int, val hAccMm: Long, val numSv: Int, val session: Int,
) {
    /** La posición es utilizable (fix 2D/3D y coordenadas distintas de 0). */
    val hasPosition: Boolean get() = fix >= 2 && (latE7 != 0 || lonE7 != 0)
}

object LiveCodec {
    const val PREFIX = "LIVE1,"
    const val FIELDS = 10
    /** Límites de las reglas de Firebase (firebase/database.rules.json, nodo `live`). */
    const val MAX_LAST = 200
    const val MAX_CHUNK = 6000

    fun fromTelemetry(t: Telemetry, tMs: Long) = LiveSample(
        tMs, t.latE7, t.lonE7, t.speedMmS, t.distanceCm, t.fixType, t.carrSoln, t.hAccMm, t.numSv, t.session.ordinal,
    )

    private fun fields(s: LiveSample) =
        "${s.tMs},${s.latE7},${s.lonE7},${s.speedMmS},${s.distCm},${s.fix},${s.carr},${s.hAccMm},${s.numSv},${s.session}"

    fun encode(s: LiveSample): String = PREFIX + fields(s)

    fun encodeChunk(list: List<LiveSample>): String {
        require(list.isNotEmpty()) { "Bloque vacío" }
        return PREFIX + list.joinToString(";") { fields(it) }
    }

    /** Decodifica `last` o un bloque `s/{n}`. Las muestras mal formadas se descartan (nunca lanza). */
    fun decode(text: String?): List<LiveSample> {
        if (text == null || !text.startsWith(PREFIX)) return emptyList()
        return text.substring(PREFIX.length).split(';').mapNotNull { part ->
            val f = part.split(',')
            if (f.size != FIELDS) return@mapNotNull null
            val n = f.map { it.toLongOrNull() ?: return@mapNotNull null }
            if (listOf(n[1], n[2], n[3]).any { it < Int.MIN_VALUE.toLong() || it > Int.MAX_VALUE.toLong() }) return@mapNotNull null
            LiveSample(n[0], n[1].toInt(), n[2].toInt(), n[3].toInt(), n[4], n[5].toInt(), n[6].toInt(), n[7], n[8].toInt(), n[9].toInt())
        }
    }

    /** Clave de la sesión en directo: fecha y hora UTC de inicio, `yyyyMMdd-HHmmss` (regla `$sid`). */
    fun sessionId(startMs: Long): String =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(startMs))
}

/** Lo que el Android tiene que escribir en Firebase. */
sealed class LiveAction {
    abstract val sid: String
    data class Start(override val sid: String, val startMs: Long) : LiveAction()
    data class State(override val sid: String, val state: String) : LiveAction()
    data class Last(override val sid: String, val line: String) : LiveAction()
    data class Chunk(override val sid: String, val index: Int, val line: String) : LiveAction()
    data class End(override val sid: String) : LiveAction()
}

/**
 * Máquina de estados pura (sin Android ni Firebase, con pruebas): recibe cada `TELEMETRY` y decide qué subir.
 * - Empieza al pasar el pecho a GRABANDO; sigue en PAUSA; termina con cualquier otro estado.
 * - `last` en cada muestra (2 Hz); bloque `s/{n}` cada [chunkMs] o al llegar a [maxPerChunk] muestras, y al terminar.
 */
class LiveRecorder(private val chunkMs: Long = 10_000L, private val maxPerChunk: Int = 40) {
    private var sid: String? = null
    private var startMs = 0L
    private var state = ""
    private var chunkIndex = 0
    private var chunkStartMs = 0L
    private val pending = ArrayList<LiveSample>()

    val activeSessionId: String? get() = sid

    fun onTelemetry(t: Telemetry, nowMs: Long): List<LiveAction> {
        val out = ArrayList<LiveAction>()
        val st = when (t.session) {
            WatchSessionState.RECORDING -> "REC"
            WatchSessionState.PAUSED -> "PAUSE"
            else -> null
        }
        if (st == null) { out += finish(); return out }
        var id = sid
        if (id == null) {
            id = LiveCodec.sessionId(nowMs)
            sid = id; startMs = nowMs; chunkIndex = 0; chunkStartMs = nowMs; pending.clear(); state = st
            out += LiveAction.Start(id, nowMs)
            if (st != "REC") out += LiveAction.State(id, st)
        } else if (st != state) {
            state = st
            out += LiveAction.State(id, st)
        }
        val s = LiveCodec.fromTelemetry(t, (nowMs - startMs).coerceAtLeast(0))
        out += LiveAction.Last(id, LiveCodec.encode(s))
        pending += s
        if (nowMs - chunkStartMs >= chunkMs || pending.size >= maxPerChunk) out += flush(id, nowMs)
        return out
    }

    /** Fin de la sesión (también si se pierde el enlace con el pecho durante mucho tiempo). */
    fun finish(): List<LiveAction> {
        val id = sid ?: return emptyList()
        val out = ArrayList<LiveAction>()
        if (pending.isNotEmpty()) out += flush(id, chunkStartMs)
        out += LiveAction.End(id)
        sid = null; pending.clear(); state = ""
        return out
    }

    private fun flush(id: String, nowMs: Long): List<LiveAction> {
        if (pending.isEmpty()) return emptyList()
        val a = LiveAction.Chunk(id, chunkIndex++, LiveCodec.encodeChunk(pending))
        pending.clear(); chunkStartMs = nowMs
        return listOf(a)
    }
}
