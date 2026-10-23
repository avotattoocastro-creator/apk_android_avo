package org.avoperformance.horse.update

/**
 * ESP32-S3 ROM serial flash commands. This is a low-level programmer:
 * caller MUST establish a verified inactive OTA partition and security state.
 * It does not modify otadata or change the boot slot.
 */
internal object FlashCommands {
    const val FLASH_BEGIN = 0x02
    const val FLASH_DATA = 0x03
    const val FLASH_END = 0x04
    const val FLASH_MD5 = 0x13
    const val BLOCK = 0x400

    private fun word(v: Long): ByteArray {
        require(v in 0..0xFFFF_FFFFL)
        return ByteArray(4) { i -> (v ushr (8 * i)).toByte() }
    }

    fun frame(opcode: Int, payload: ByteArray, checksum: Int = 0): ByteArray {
        require(opcode in setOf(FLASH_BEGIN, FLASH_DATA, FLASH_END, FLASH_MD5))
        require(payload.size <= 65535)
        val header = byteArrayOf(0, opcode.toByte(),
            (payload.size and 255).toByte(), (payload.size ushr 8).toByte(),
            checksum.toByte(), 0, 0, 0)
        val bytes = header + payload
        val result = ArrayList<Byte>(bytes.size + 2)
        result.add(0xC0.toByte())
        for (b in bytes) {
            when (b.toInt() and 255) {
                0xC0 -> { result.add(0xDB.toByte()); result.add(0xDC.toByte()) }
                0xDB -> { result.add(0xDB.toByte()); result.add(0xDD.toByte()) }
                else -> result.add(b)
            }
        }
        result.add(0xC0.toByte())
        return result.toByteArray()
    }

    fun begin(address: Long, imageBytes: Int): ByteArray {
        require(address >= 0x10000 && address % 0x10000L == 0L)
        require(imageBytes in 1..0x600000)
        val blocks = (imageBytes + BLOCK - 1) / BLOCK
        val eraseBytes = blocks.toLong() * BLOCK
        // ROM FLASH_BEGIN payload: erase size, blocks, block size, offset.
        return frame(FLASH_BEGIN, word(eraseBytes) + word(blocks.toLong()) +
            word(BLOCK.toLong()) + word(address))
    }

    fun data(sequence: Int, bytes: ByteArray): ByteArray {
        require(sequence >= 0 && bytes.size == BLOCK)
        val payload = word(BLOCK.toLong()) + word(sequence.toLong()) +
            word(0) + word(0) + bytes
        val checksum = bytes.fold(0xEF) { sum, b -> sum xor (b.toInt() and 255) }
        return frame(FLASH_DATA, payload, checksum)
    }

    fun endWithoutReboot(): ByteArray = frame(FLASH_END, word(1))
    fun md5(address: Long, size: Long): ByteArray {
        require(address >= 0 && size > 0 && size <= 0x600000)
        return frame(FLASH_MD5, word(address) + word(size) + word(0) + word(0))
    }
}
