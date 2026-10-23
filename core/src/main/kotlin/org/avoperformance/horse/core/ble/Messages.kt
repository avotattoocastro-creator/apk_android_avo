package org.avoperformance.horse.core.ble

import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.bytes.ByteWriter

// Decoders for the payloads the watch firmware sends. Layouts copied from
// ble_service.cpp / storage.cpp (V3.4.3 + V3.4.4). Fields that a firmware
// version does not send are null — never invented.

enum class WatchSessionState(val texto: String) {
    IDLE("En espera"), ARMED("Armado"), RECORDING("Grabando"), PAUSED("En pausa"),
    STOPPED_WAITING_UPLOAD("Detenido (pendiente de subir)"), COMPLETED("Completado"), RECOVERY("Recuperación"), ERROR("Error");
    companion object { fun of(v: Int) = values().getOrElse(v) { ERROR } }
}

enum class GeofenceState(val texto: String) {
    AUTO_DISABLED("Automático desactivado"), WAITING_GNSS("Esperando GNSS"), OUTSIDE("Fuera"), ENTRY_PENDING("Confirmando entrada"),
    INSIDE("Dentro"), RECORDING("Grabando"), EXIT_PENDING("Confirmando salida"), POST_RECORDING("Post-grabación"),
    PAUSED("En pausa"), ERROR("Error de geocerca");
    companion object { fun of(v: Int) = values().getOrElse(v) { ERROR } }
}

enum class RecStatus(val texto: String) {
    IDLE("En espera"), RECORDING("Grabando"), TEMP_BUFFER("Buffer temporal"), REC_ERROR("Error de grabación");
    companion object { fun of(v: Int) = values().getOrElse(v) { REC_ERROR } }
}

enum class PowerLevel { NORMAL, LOW, CRITICAL, UNKNOWN; companion object { fun of(v: Int) = values().getOrElse(v) { UNKNOWN } } }
enum class TimeSource { NONE, RTC, PHONE, GNSS; companion object { fun of(v: Int) = values().getOrElse(v) { NONE } } }

/** UBX NAV-PVT flags3.lastCorrectionAge → upper bound in ms (null = not available). */
fun correctionAgeMaxMs(code: Int): Long? = when (code and 0x0F) {
    0 -> null; 1 -> 1000; 2 -> 2000; 3 -> 5000; 4 -> 10000; 5 -> 15000; 6 -> 20000; 7 -> 30000
    8 -> 45000; 9 -> 60000; 10 -> 90000; 11 -> 120000; else -> Long.MAX_VALUE
}

data class WatchInfo(
    val bleProto: Int, val uartProto: Int, val rawFormat: Int, val configSchema: Int,
    val firmware: String, val deviceId: String, val bootCount: Long, val mtu: Int, val caps: Long,
    // V3.4.4+
    val authorized: Boolean?, val authKeys: Int?, val claimPending: Boolean?, val authRequired: Boolean?, val buildFingerprint: String?,
) {
    val supportsAuth get() = caps and 0x80L != 0L
    val supportsTelemetryV2 get() = caps and 0x100L != 0L
    val supportsReboot get() = caps and 0x200L != 0L

    companion object {
        fun decode(p: ByteArray): WatchInfo? {
            val r = ByteReader(p)
            val bp = r.u8(); val up = r.u8(); val rf = r.u16(); val cs = r.u16()
            val fw = r.str(16); val dev = r.str(16); val boot = r.u32(); val mtu = r.u16(); val caps = r.u32()
            if (!r.ok) return null
            var a: Boolean? = null; var k: Int? = null; var cp: Boolean? = null; var req: Boolean? = null; var fp: String? = null
            if (r.remaining >= 4) { a = r.u8() != 0; k = r.u8(); cp = r.u8() != 0; req = r.u8() != 0 }
            if (r.remaining >= 32) fp = r.str(32)
            return WatchInfo(bp, up, rf, cs, fw, dev, boot, mtu, caps, a, k, cp, req, fp)
        }
    }
}

data class WatchStatus(
    val session: WatchSessionState, val geofence: GeofenceState, val rec: RecStatus, val sdMounted: Boolean,
    val sdFreeBytes: Long, val sessionId: String, val manual: Boolean, val inhibited: Boolean,
    val batteryPct: Int?, val batteryMv: Int, val vbus: Boolean, val power: PowerLevel, val backLink: Boolean,
    val girth: Boolean, val rtcmFlowing: Boolean, val wallMs: Long, val timeSource: TimeSource, val droppedRecords: Long,
    val ringPermille: Int,
) {
    companion object {
        fun decode(p: ByteArray): WatchStatus? {
            val r = ByteReader(p)
            val s = WatchStatus(
                WatchSessionState.of(r.u8()), GeofenceState.of(r.u8()), RecStatus.of(r.u8()), r.u8() != 0, r.u64(), r.str(24),
                r.u8() != 0, r.u8() != 0, r.i8().let { if (it < 0) null else it }, r.u16(), r.u8() != 0, PowerLevel.of(r.u8()),
                r.u8() != 0, r.u8() != 0, r.u8() != 0, r.u64(), TimeSource.of(r.u8()), r.u32(), r.u16(),
            )
            return if (r.ok) s else null
        }
    }
}

/** TELEMETRY notification (2 Hz). v1 = 45 bytes (V3.3–V3.4.3), v2 = 83 bytes (V3.4.4). */
data class Telemetry(
    val session: WatchSessionState, val geofence: GeofenceState, val rec: RecStatus,
    val fixType: Int, val carrSoln: Int, val numSv: Int, val hAccMm: Long,
    val latE7: Int, val lonE7: Int, val speedMmS: Int, val distanceCm: Long, val activeMs: Long,
    val batteryPct: Int?, val backLink: Boolean, val girth: Boolean, val rtcmFlowing: Boolean,
    val ringPermille: Int, val droppedRecords: Long, val pendingMs: Long, val inhibited: Boolean,
    val v2: TelemetryV2?,
) {
    companion object {
        const val V1_LEN = 45
        const val V2_LEN = 83
        fun decode(p: ByteArray): Telemetry? {
            if (p.size < V1_LEN) return null
            val r = ByteReader(p)
            val t = Telemetry(
                WatchSessionState.of(r.u8()), GeofenceState.of(r.u8()), RecStatus.of(r.u8()), r.u8(), r.u8(), r.u8(), r.u32(),
                r.i32(), r.i32(), r.i32(), r.u32(), r.u32(), r.i8().let { if (it < 0) null else it }, r.u8() != 0,
                r.u8() != 0, r.u8() != 0, r.u16(), r.u32(), r.u32(), r.u8() != 0, null,
            )
            if (!r.ok) return null
            if (p.size < V2_LEN) return t
            val v2 = TelemetryV2(
                r.u8(), r.u8(), r.u8() != 0, r.u8().let { if (it == 0xFF) null else it }, r.u16().let { if (it == 0) null else it },
                TimeSource.of(r.u8()), r.u8() != 0, r.u32(), r.u32(), PowerLevel.of(r.u8()), r.u8() != 0, r.u16(),
                r.u32().let { if (it == 0xFFFFFFFFL) null else it }, r.u32(), r.u32().let { if (it == 0xFFFFFFFFL) null else it },
                r.u8() != 0, r.u8() != 0, r.u32(),
            )
            return if (r.ok) t.copy(v2 = v2) else t
        }
    }
}

data class TelemetryV2(
    val gnssFlags: Int, val corrAgeCode: Int, val sdMounted: Boolean, val ppsState: Int?, val backBatteryMv: Int?,
    val timeSource: TimeSource, val backStatusValid: Boolean, val rtcmToBackBytes: Long, val rtcmUsedByReceiver: Long,
    val power: PowerLevel, val vbus: Boolean, val batteryMv: Int, val gnssAgeMs: Long?, val vAccMm: Long, val linkAgeMs: Long?,
    val manualSession: Boolean, val girthPresent: Boolean, val girthLost: Long,
) {
    val gnssFixOk get() = gnssFlags and 1 != 0
    val diffSoln get() = gnssFlags and 2 != 0
    val invalidLlh get() = gnssFlags and 4 != 0
    val haveGnss get() = gnssFlags and 8 != 0
    val qualityOk get() = gnssFlags and 16 != 0
}

data class RtcmAck(val freeBytes: Long, val expectedSeq: Long, val droppedBytes: Long) {
    companion object {
        fun decode(p: ByteArray): RtcmAck? {
            val r = ByteReader(p)
            val a = RtcmAck(r.u32(), r.u32(), r.u32())
            return if (r.ok) a else null
        }
    }
}

enum class WatchFileState(val texto: String) {
    UNKNOWN("Desconocido"), OPEN("Abierta / grabando"), CLOSED("Cerrada"), CLOSED_RECOVERED("Recuperada tras corte"), UPLOADED("Marcada como subida");
    companion object { fun of(v: Int) = values().getOrElse(v) { UNKNOWN } }
}

data class WatchSessionEntry(
    val sessionId: String, val state: WatchFileState, val segments: Int, val totalBytes: Long, val startRtcMs: Long,
    val activeMs: Long, val recordingNow: Boolean,
)

data class SessionListPage(val page: Int, val entries: List<WatchSessionEntry>, val more: Boolean) {
    companion object {
        fun decode(p: ByteArray): SessionListPage? {
            val r = ByteReader(p)
            val page = r.u16()
            val n = r.u8()
            val list = ArrayList<WatchSessionEntry>(n)
            repeat(n) {
                list += WatchSessionEntry(r.str(24), WatchFileState.of(r.u8()), r.u16(), r.u64(), r.u64(), r.u32(), r.u8() != 0)
            }
            val more = r.u8() != 0
            return if (r.ok) SessionListPage(page, list, more) else null
        }
    }
}

data class FileChunk(val offset: Long, val fileSize: Long, val crc32: Long, val data: ByteArray) {
    companion object {
        fun decode(p: ByteArray): FileChunk? {
            if (p.size < 12) return null
            val r = ByteReader(p)
            return FileChunk(r.u32(), r.u32(), r.u32(), r.rest())
        }
    }
}

data class BlackboxRecord(val seq: Long, val uptimeMs: Long, val rtcS: Long, val boot: Long, val code: Int, val severity: Int, val arg0: Long, val arg1: Long) {
    companion object {
        const val SIZE = 27
        fun decodeList(p: ByteArray): List<BlackboxRecord> {
            val r = ByteReader(p)
            val n = r.u8()
            val out = ArrayList<BlackboxRecord>()
            repeat(n) {
                val rec = BlackboxRecord(r.u32(), r.u32(), r.u32(), r.u32(), r.u16(), r.u8(), r.u32(), r.u32())
                if (r.ok) out += rec
            }
            return out
        }
        fun codeName(c: Int): String = when (c) {
            1 -> "ARRANQUE"; 2 -> "APAGADO"; 3 -> "MOTIVO_RESET"; 4 -> "WATCHDOG"; 5 -> "BROWNOUT"; 6 -> "PANIC"
            10 -> "ERROR_SD"; 11 -> "SD_REMONTADA"; 12 -> "SD_LLENA"; 13 -> "BUFFER_SATURADO"; 14 -> "REGISTROS_PERDIDOS"
            20 -> "UART_PERDIDO"; 21 -> "UART_RECUPERADO"; 22 -> "UART_CRC"
            30 -> "BLE_CONEXION"; 31 -> "BLE_DESCONEXION"; 32 -> "BLE_AUTH_FALLIDA"
            40 -> "RTCM_PERDIDO"; 41 -> "RTCM_RECUPERADO"; 42 -> "RTCM_DESBORDADO"
            50 -> "GNSS_PERDIDO"; 51 -> "GNSS_RECUPERADO"; 52 -> "CAMBIO_RTK"
            60 -> "BATERIA_BAJA"; 61 -> "BATERIA_CRITICA"
            70 -> "SESION_INICIO"; 71 -> "SESION_FIN"; 72 -> "SESION_PAUSA"; 73 -> "SESION_REANUDA"; 74 -> "SESION_RECUPERADA"; 75 -> "SESION_REANUDADA_TRAS_REINICIO"
            80 -> "GEOCERCA"; 90 -> "CONFIG_CAMBIADA"; 91 -> "CONFIG_CORRUPTA"; 100 -> "OTA"; 110 -> "PREBUFFER_REDUCIDO"
            else -> "CODIGO_$c"
        }
    }
}

/**
 * DIAG_GET returns "k=v k=v …". Some values contain spaces ("rec=BUFFER TEMPORAL"),
 * so a value extends until the next " key=".
 */
object DiagParser {
    private val key = Regex("(?:^| )([a-z_]+)=")
    fun parse(text: String): LinkedHashMap<String, String> {
        val out = LinkedHashMap<String, String>()
        val ms = key.findAll(text).toList()
        for ((i, m) in ms.withIndex()) {
            val start = m.range.last + 1
            val end = if (i + 1 < ms.size) ms[i + 1].range.first else text.length
            out[m.groupValues[1]] = text.substring(start, end).trim()
        }
        return out
    }
}

/** Request payload builders (exact layouts expected by dispatch() in the firmware). */
object Requests {
    fun sessionCmd(cmd: SessionCmd, confirmed: Boolean): ByteArray = byteArrayOf(cmd.code.toByte(), if (confirmed) 1 else 0)
    fun listSessions(page: Int): ByteArray = ByteWriter().u16(page).toByteArray()
    fun readFile(sessionId: String, segment: Int, offset: Long, length: Int): ByteArray =
        ByteWriter().str(sessionId, 24).u16(segment).u32(offset).u32(length.toLong()).toByteArray()
    fun sessionOnly(sessionId: String): ByteArray = ByteWriter().str(sessionId, 24).toByteArray()
    fun markUploaded(sessionId: String, sha256: ByteArray): ByteArray { require(sha256.size == 32); return ByteWriter().str(sessionId, 24).bytes(sha256).toByteArray() }
    fun deleteCommit(sessionId: String, token: Long, force: Boolean): ByteArray = ByteWriter().str(sessionId, 24).u32(token).u8(if (force) 1 else 0).toByteArray()
    fun setActiveFences(mask: Int, auto: Boolean): ByteArray = byteArrayOf(mask.toByte(), if (auto) 1 else 0)
    fun getFence(slot: Int): ByteArray = byteArrayOf(slot.toByte())
    fun timeSet(unixMs: Long): ByteArray = ByteWriter().u64(unixMs).toByteArray()
    fun blackbox(n: Int): ByteArray = byteArrayOf(n.coerceIn(1, 100).toByte())
    fun reboot(force: Boolean): ByteArray = byteArrayOf(1, if (force) 1 else 0)
    fun authHello(keyId: ByteArray, phoneNonce: ByteArray): ByteArray = ByteWriter().bytes(keyId).bytes(phoneNonce).toByteArray()
    fun claimBegin(phoneName: String): ByteArray = ByteWriter().str(phoneName, 24).toByteArray()
    /** RTCM write: u32 sequence + raw RTCM bytes (single fragment, sent on the RTCM characteristic). */
    fun rtcmWrite(seq: Long, data: ByteArray, off: Int, len: Int, msgId: Int): ByteArray {
        val p = ByteWriter(len + 4).u32(seq).bytes(data, off, len).toByteArray()
        return BleFraming.build(MsgType.RTCM.code, msgId, 0, 1, 0, 0, p)
    }
    /** Max RTCM bytes per write for an ATT payload size (MTU-3). */
    fun rtcmMaxChunk(attPayload: Int): Int = attPayload - BleFraming.OVERHEAD - 4
}
