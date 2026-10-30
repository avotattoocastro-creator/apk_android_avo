package org.avoperformance.horse.update

/**
 * Decoder for Espressif ROM serial bootloader SLIP replies.
 * [command] is restricted to read-only diagnostics; flash commands go through [EspRom].
 */
internal object RomProtocol {
    data class Reply(val opcode: Int, val payload: ByteArray, val value: Long)

    fun decodeFrames(data: ByteArray): List<ByteArray> {
        val frames = mutableListOf<ByteArray>()
        val current = ArrayList<Byte>()
        var started = false
        var escaped = false
        for (b in data) {
            val n = b.toInt() and 255
            if (n == 0xC0) {
                if (started && current.isNotEmpty() && !escaped) frames.add(current.toByteArray())
                current.clear()
                started = true
                escaped = false
            } else if (started) {
                if (escaped) {
                    when (n) {
                        0xDC -> current.add(0xC0.toByte())
                        0xDD -> current.add(0xDB.toByte())
                        else -> { current.clear(); started = false }
                    }
                    escaped = false
                } else if (n == 0xDB) escaped = true
                else current.add(b)
            }
        }
        return frames
    }

    fun parseReply(frame: ByteArray): Reply? {
        if (frame.size < 8 || (frame[0].toInt() and 255) != 1) return null
        val size = (frame[2].toInt() and 255) or ((frame[3].toInt() and 255) shl 8)
        if (size != frame.size - 8) return null
        val value = (4..7).fold(0L) { acc, i -> acc or ((frame[i].toLong() and 255L) shl ((i - 4) * 8)) }
        return Reply(frame[1].toInt() and 255, frame.copyOfRange(8, frame.size), value)
    }

    /** Espressif ROM request: 8-byte header + SLIP framing. No flash write opcodes. */
    fun command(opcode: Int, payload: ByteArray): ByteArray {
        require(opcode == 0x08 || opcode == 0x0A) { "Solo SYNC y READ_REG" }
        val packet = byteArrayOf(0, opcode.toByte(), (payload.size and 255).toByte(),
            (payload.size ushr 8).toByte(), 0, 0, 0, 0) + payload
        val encoded = ArrayList<Byte>()
        encoded.add(0xC0.toByte())
        for (b in packet) {
            when (b.toInt() and 255) {
                0xC0 -> { encoded.add(0xDB.toByte()); encoded.add(0xDC.toByte()) }
                0xDB -> { encoded.add(0xDB.toByte()); encoded.add(0xDD.toByte()) }
                else -> encoded.add(b)
            }
        }
        encoded.add(0xC0.toByte())
        return encoded.toByteArray()
    }

    /** General ROM request (any opcode). Used by [EspRom]; diagnostics keep using [command]. */
    fun encodeRequest(opcode: Int, payload: ByteArray, checksum: Int = 0): ByteArray {
        require(opcode in 0..255 && payload.size <= 0xFFFF)
        val packet = byteArrayOf(0, opcode.toByte(), (payload.size and 255).toByte(),
            (payload.size ushr 8).toByte()) + le32(checksum.toLong() and 0xFFFF_FFFFL) + payload
        return slipEncode(packet)
    }

    fun slipEncode(packet: ByteArray): ByteArray {
        val out = java.io.ByteArrayOutputStream(packet.size + 16)
        out.write(0xC0)
        for (b in packet) {
            when (b.toInt() and 255) {
                0xC0 -> { out.write(0xDB); out.write(0xDC) }
                0xDB -> { out.write(0xDB); out.write(0xDD) }
                else -> out.write(b.toInt() and 255)
            }
        }
        out.write(0xC0)
        return out.toByteArray()
    }

    /**
     * Incremental SLIP decoder: keeps partial frames between USB packets and
     * discards any text printed outside frames (ROM boot banner, app logs).
     */
    class SlipStream {
        private val current = java.io.ByteArrayOutputStream()
        private var inFrame = false
        private var escaped = false

        fun feed(data: ByteArray, length: Int = data.size): List<ByteArray> {
            val frames = mutableListOf<ByteArray>()
            for (i in 0 until length) {
                val n = data[i].toInt() and 255
                if (n == 0xC0) {
                    if (inFrame && current.size() > 0 && !escaped) frames.add(current.toByteArray())
                    current.reset()
                    inFrame = true
                    escaped = false
                } else if (inFrame) {
                    if (escaped) {
                        escaped = false
                        when (n) {
                            0xDC -> current.write(0xC0)
                            0xDD -> current.write(0xDB)
                            else -> { current.reset(); inFrame = false } // corrupt escape: resync
                        }
                    } else if (n == 0xDB) escaped = true
                    else current.write(n)
                    if (current.size() > 0x10000) { current.reset(); inFrame = false }
                }
            }
            return frames
        }

        fun reset() { current.reset(); inFrame = false; escaped = false }
    }

    fun syncReport(raw: ByteArray): String {
        val frames = decodeFrames(raw)
        val replies = frames.mapNotNull(::parseReply)
        val sync = replies.firstOrNull { it.opcode == 0x08 }
        return when {
            sync == null -> "SYNC ROM NO VALIDADO. Tramas completas: ${frames.size}. Respuestas válidas: ${replies.size}."
            sync.payload.size < 2 -> "SYNC ROM recibido, estado insuficiente. Escritura bloqueada."
            // esptool: the status byte is the first byte after the response data (none for SYNC).
            sync.payload[0].toInt() != 0 ->
                "SYNC ROM respondió con estado no satisfactorio. Escritura bloqueada."
            else -> "SYNC ROM VALIDADO (respuesta opcode 0x08, estado 00 00). Identidad y particiones aún sin verificar. Escritura bloqueada."
        }
    }
}
