package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test

class FlashCommandsTest {
    private fun decoded(encoded: ByteArray) = RomProtocol.decodeFrames(encoded).single()
    private fun uint(bytes: ByteArray, p: Int): Long =
        (0..3).fold(0L) { a, i -> a or ((bytes[p + i].toLong() and 255) shl (8 * i)) }

    @Test fun beginUsesInactiveAddressAndPaddedBlockCount() {
        val frame = decoded(FlashCommands.begin(0x610000, 1364544))
        assertEquals(FlashCommands.FLASH_BEGIN, frame[1].toInt() and 255)
        assertEquals(0x610000L, uint(frame, 20))
        assertEquals(FlashCommands.BLOCK.toLong(), uint(frame, 16))
        assertEquals((1364544L + 1023) / 1024, uint(frame, 12))
    }

    @Test fun flashDataSequenceAndChecksum() {
        val block = ByteArray(FlashCommands.BLOCK) { 0xFF.toByte() }
        block[0] = 0xC0.toByte()
        block[1] = 0xDB.toByte()
        val frame = decoded(FlashCommands.data(7, block))
        assertEquals(FlashCommands.FLASH_DATA, frame[1].toInt() and 255)
        assertEquals(7L, uint(frame, 12))
        assertEquals(FlashCommands.BLOCK.toLong(), uint(frame, 8))
        assertArrayEquals(block, frame.copyOfRange(24, frame.size))
        val expected = block.fold(0xEF) { sum, b -> sum xor (b.toInt() and 255) }
        assertEquals(expected, frame[4].toInt() and 255)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsUnalignedFlashAddress() { FlashCommands.begin(0x610001, 1000) }
}
