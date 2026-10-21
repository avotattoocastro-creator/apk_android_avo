package org.avoperformance.horse.core.ble

import org.avoperformance.horse.core.bytes.ByteWriter
import org.avoperformance.horse.core.bytes.Crc
import org.avoperformance.horse.core.bytes.leU16
import java.util.UUID

/**
 * AVO BLE PROTOCOL v1 — taken from the watch firmware V3.4.3/V3.4.4
 * (src/ble_service.cpp + lib/avo_core/src/avo_ble_proto.*). Nothing here is
 * invented: every UUID, type and layout is the one the firmware implements.
 */
object AvoGatt {
    val SERVICE: UUID = UUID.fromString("7a5e0001-4156-4f50-8e1f-3c0de5a1c0a3")
    val INFO: UUID = UUID.fromString("7a5e0002-4156-4f50-8e1f-3c0de5a1c0a3")     // read (encrypted)
    val CTRL_RX: UUID = UUID.fromString("7a5e0003-4156-4f50-8e1f-3c0de5a1c0a3")  // write with response (encrypted)
    val CTRL_TX: UUID = UUID.fromString("7a5e0004-4156-4f50-8e1f-3c0de5a1c0a3")  // notify: responses, RTCM_ACK, events
    val TELEM: UUID = UUID.fromString("7a5e0005-4156-4f50-8e1f-3c0de5a1c0a3")    // notify: telemetry 2 Hz
    val RTCM: UUID = UUID.fromString("7a5e0006-4156-4f50-8e1f-3c0de5a1c0a3")     // write without response (encrypted)
    val FILE_TX: UUID = UUID.fromString("7a5e0007-4156-4f50-8e1f-3c0de5a1c0a3")  // notify: FILE_DATA
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    /** V3.4.2+: "AVO_XXXX"; V3.3: "AVO-XXXX". */
    val NAME_REGEX = Regex("^AVO[_-][0-9A-F]{4}$")
    const val PREFERRED_MTU = 247
}

enum class MsgType(val code: Int) {
    GET_INFO(0x01), GET_STATUS(0x02),
    AUTH_HELLO(0x08), AUTH_PROOF(0x09), CLAIM_BEGIN(0x0A), CLAIM_RESULT(0x0B), AUTH_REVOKE(0x0C),
    SESSION_CMD(0x10),
    GET_CONFIG(0x20), SET_CONFIG(0x21), SET_FENCE(0x22), GET_FENCE(0x23), SET_ACTIVE_FENCES(0x24),
    RTCM(0x30), RTCM_ACK(0x31),
    LIST_SESSIONS(0x40), READ_FILE(0x41), FILE_SHA256(0x42), MARK_UPLOADED(0x43),
    DELETE_PREPARE(0x44), DELETE_COMMIT(0x45), FILE_DATA(0x46),
    OTA_BEGIN(0x50), OTA_DATA(0x51), OTA_END(0x52), OTA_ABORT(0x53),
    DIAG_GET(0x60), BLACKBOX_READ(0x61), REBOOT(0x62),
    TIME_SET(0x70), CREDITS(0x71),
    NACK(0x7E), ACK(0x7F),
    TELEMETRY(0x80), EVENT(0x81);

    companion object {
        private val map = values().associateBy { it.code }
        fun of(code: Int): MsgType? = map[code]
    }
}

enum class BleStatus(val code: Int, val texto: String) {
    OK(0, "correcto"), BAD_CRC(1, "CRC erróneo"), BAD_FORMAT(2, "formato erróneo"), UNKNOWN_TYPE(3, "comando no soportado por el firmware"),
    BUSY(4, "ocupado"), NOT_ALLOWED(5, "no permitido"), NOT_FOUND(6, "no encontrado"), TOO_LARGE(7, "demasiado grande"),
    AUTH_REQUIRED(8, "autorización necesaria"), IO_ERROR(9, "error de E/S"), STATE_CONFLICT(10, "estado incompatible"),
    DUPLICATE(11, "duplicado (ya ejecutado)"), TIMEOUT(12, "tiempo agotado"), VERIFY_FAILED(13, "verificación fallida"),
    UNKNOWN(255, "desconocido");

    companion object {
        fun of(code: Int): BleStatus = values().firstOrNull { it.code == code } ?: UNKNOWN
    }
}

object BleFlags { const val ACK_REQ = 0x01; const val RESPONSE = 0x02; const val ERROR = 0x04 }

enum class SessionCmd(val code: Int) { START(1), STOP(2), PAUSE(3), RESUME(4), MARKER(5), REARM(6) }

/** One application fragment (one ATT write or notification). */
data class BleFrag(
    val ver: Int, val type: Int, val msgId: Int, val idx: Int, val cnt: Int, val flags: Int, val status: Int,
    val payload: ByteArray,
) {
    val isResponse get() = flags and BleFlags.RESPONSE != 0
}

object BleFraming {
    const val VERSION = 1
    const val HDR = 10
    const val OVERHEAD = HDR + 2
    const val MAX_MSG = 4096          // firmware reassembly limit for requests

    fun parse(p: ByteArray): BleFrag? {
        if (p.size < OVERHEAD) return null
        val want = leU16(p, p.size - 2)
        if (Crc.crc16(p, 0, p.size - 2) != want) return null
        val ver = p[0].toInt() and 0xFF
        val cnt = leU16(p, 6)
        val idx = leU16(p, 4)
        if (ver == 0 || cnt == 0 || idx >= cnt) return null
        return BleFrag(ver, p[1].toInt() and 0xFF, leU16(p, 2), idx, cnt, p[8].toInt() and 0xFF, p[9].toInt() and 0xFF,
            p.copyOfRange(HDR, p.size - 2))
    }

    fun build(type: Int, msgId: Int, idx: Int, cnt: Int, flags: Int, status: Int, payload: ByteArray, off: Int = 0, len: Int = payload.size): ByteArray {
        require(cnt > 0 && idx < cnt)
        val w = ByteWriter(len + OVERHEAD)
        w.u8(VERSION).u8(type).u16(msgId).u16(idx).u16(cnt).u8(flags).u8(status).bytes(payload, off, len)
        val body = w.toByteArray()
        return ByteWriter(body.size + 2).bytes(body).u16(Crc.crc16(body)).toByteArray()
    }

    /** Fragment count for an ATT payload size (MTU - 3), as ble_frag_count() in the firmware. */
    fun count(len: Int, attPayload: Int): Int {
        require(attPayload > OVERHEAD)
        val per = attPayload - OVERHEAD
        val c = (len + per - 1) / per
        return if (c == 0) 1 else c
    }

    fun fragment(type: Int, msgId: Int, payload: ByteArray, attPayload: Int, flags: Int = BleFlags.ACK_REQ): List<ByteArray> {
        require(payload.size <= MAX_MSG) { "mensaje BLE de ${payload.size} B supera ${MAX_MSG} B" }
        val cnt = count(payload.size, attPayload)
        val per = attPayload - OVERHEAD
        return (0 until cnt).map { i ->
            val off = i * per
            build(type, msgId, i, cnt, flags, 0, payload, off, minOf(per, payload.size - off))
        }
    }
}

/** A complete message received from the watch. */
data class BleMessage(val type: Int, val msgId: Int, val flags: Int, val status: Int, val payload: ByteArray) {
    val isResponse get() = flags and BleFlags.RESPONSE != 0
    val statusEnum get() = BleStatus.of(status)
    val msgType get() = MsgType.of(type)
}

/**
 * Reassembles notifications. The firmware sends the fragments of one message
 * contiguously and in order; a gap or CRC error discards that message (the
 * request is retried by the caller with the same msg_id).
 */
class BleReassembler(private val maxMsg: Int = 64 * 1024) {
    private data class Slot(val type: Int, val msgId: Int, val cnt: Int, var next: Int, val buf: java.io.ByteArrayOutputStream, val flags: Int, val status: Int)
    private val slots = HashMap<Long, Slot>()
    var crcErrors = 0; private set
    var gaps = 0; private set

    fun feed(raw: ByteArray): BleMessage? {
        val f = BleFraming.parse(raw) ?: run { crcErrors++; return null }
        val key = (f.type.toLong() shl 16) or f.msgId.toLong()
        if (f.cnt == 1) { slots.remove(key); return BleMessage(f.type, f.msgId, f.flags, f.status, f.payload) }
        var s = slots[key]
        if (f.idx == 0) {
            s = Slot(f.type, f.msgId, f.cnt, 0, java.io.ByteArrayOutputStream(), f.flags, f.status)
            slots[key] = s
        }
        if (s == null || f.idx != s.next || f.cnt != s.cnt) { gaps++; slots.remove(key); return null }
        s.buf.write(f.payload)
        if (s.buf.size() > maxMsg) { slots.remove(key); gaps++; return null }
        s.next++
        if (s.next < s.cnt) return null
        slots.remove(key)
        return BleMessage(s.type, s.msgId, s.flags, s.status, s.buf.toByteArray())
    }

    fun reset() { slots.clear() }
}
