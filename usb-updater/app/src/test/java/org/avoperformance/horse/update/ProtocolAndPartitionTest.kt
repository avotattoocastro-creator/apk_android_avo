package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test
import java.security.MessageDigest

class ProtocolAndPartitionTest {
    @Test fun slipSyncReply() {
        val raw = byteArrayOf(0xC0.toByte(), 1, 8, 4, 0, 7, 7, 0x12, 0x20, 0, 0, 0, 0, 0xC0.toByte())
        val replies = RomProtocol.decodeFrames(raw).mapNotNull(RomProtocol::parseReply)
        assertEquals(1, replies.size)
        assertEquals(8, replies.single().opcode)
        assertTrue(RomProtocol.syncReport(raw).contains("VALIDADO"))
    }

    @Test fun slipEscapingAndFragmentedData() {
        val packet = RomProtocol.command(0x0A, byteArrayOf(0xC0.toByte(), 0xDB.toByte()))
        val frames = RomProtocol.decodeFrames(packet)
        assertEquals(1, frames.size)
        assertArrayEquals(byteArrayOf(0, 0x0A, 2, 0, 0, 0, 0, 0, 0xC0.toByte(), 0xDB.toByte()), frames.single())
        assertTrue(RomProtocol.decodeFrames(packet.copyOf(packet.size - 1)).isEmpty())
    }

    @Test(expected = IllegalArgumentException::class)
    fun noFlashWriteOpcode() { RomProtocol.command(0x03, byteArrayOf()) }

    private fun put32(bytes: ByteArray, pos: Int, n: Long) {
        repeat(4) { bytes[pos + it] = (n ushr (8 * it)).toByte() }
    }

    private fun entry(bytes: ByteArray, slot: Int, type: Int, subtype: Int, offset: Long, size: Long, name: String) {
        val p = slot * 32
        bytes[p] = 0xAA.toByte()
        bytes[p + 1] = 0x50
        bytes[p + 2] = type.toByte()
        bytes[p + 3] = subtype.toByte()
        put32(bytes, p + 4, offset)
        put32(bytes, p + 8, size)
        name.toByteArray().copyInto(bytes, p + 12)
        bytes[p + 12 + name.length] = 0
    }

    private fun historicalTable(): ByteArray {
        val bytes = ByteArray(256) { 0xFF.toByte() }
        entry(bytes, 0, 1, 2, 0x9000, 0x5000, "nvs")
        entry(bytes, 1, 1, 0, 0xE000, 0x2000, "otadata")
        entry(bytes, 2, 0, 0x10, 0x10000, 0x600000, "app0")
        entry(bytes, 3, 0, 0x11, 0x610000, 0x600000, "app1")
        entry(bytes, 4, 1, 0x40, 0xC10000, 0x40000, "blackbox")
        entry(bytes, 5, 1, 3, 0xC50000, 0x10000, "coredump")
        return bytes
    }

    @Test fun historicalTableParses() {
        val result = PartitionTable.parse(historicalTable(), 0x1000000)
        assertEquals(6, result.entries.size)
        assertEquals(2, result.entries.count { it.isOtaApp })
    }

    @Test fun validMd5Accepted() {
        val bytes = historicalTable()
        val p = 6 * 32
        bytes[p] = 0xEB.toByte()
        bytes[p + 1] = 0xEB.toByte()
        MessageDigest.getInstance("MD5").digest(bytes.copyOfRange(0, p)).copyInto(bytes, p + 16)
        assertTrue(PartitionTable.parse(bytes, 0x1000000).hasMd5Record)
    }

    @Test(expected = IllegalArgumentException::class)
    fun modifiedTableRejectedByMd5() {
        val bytes = historicalTable()
        val p = 6 * 32
        bytes[p] = 0xEB.toByte()
        bytes[p + 1] = 0xEB.toByte()
        MessageDigest.getInstance("MD5").digest(bytes.copyOfRange(0, p)).copyInto(bytes, p + 16)
        bytes[16] = 1
        PartitionTable.parse(bytes, 0x1000000)
    }

    @Test(expected = IllegalArgumentException::class)
    fun overlappingPartitionsRejected() {
        val bytes = historicalTable()
        put32(bytes, 3 * 32 + 4, 0x20000)
        PartitionTable.parse(bytes, 0x1000000)
    }
}
