package org.avoperformance.horse.update

/**
 * Decoder for Espressif ROM serial bootloader SLIP replies.
 * Read-only protocol diagnostics. Does not issue flash commands.
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

    fun syncReport(raw: ByteArray): String {
        val frames = decodeFrames(raw)
        val replies = frames.mapNotNull(::parseReply)
        val sync = replies.firstOrNull { it.opcode == 0x08 }
        return when {
            sync == null -> "SYNC ROM NO VALIDADO. Tramas completas: ${frames.size}. Respuestas válidas: ${replies.size}."
            sync.payload.size < 2 -> "SYNC ROM recibido, estado insuficiente. Escritura bloqueada."
            sync.payload[sync.payload.size - 2].toInt() != 0 || sync.payload.last().toInt() != 0 ->
                "SYNC ROM respondió con estado no satisfactorio. Escritura bloqueada."
            else -> "SYNC ROM VALIDADO (respuesta opcode 0x08, estado 00 00). Identidad y particiones aún sin verificar. Escritura bloqueada."
        }
    }
}
