package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test

/** otadata logic checked against ESP-IDF rules and reference CRC values. */
class OtaDataTest {
    private fun entry(seq: Long, state: Long = OtaData.STATE_VALID, crc: Long = OtaData.seqCrc(seq)): OtaData.Entry {
        val e = ByteArray(32) { 0xFF.toByte() }
        le32(seq).copyInto(e, 0); le32(state).copyInto(e, 24); le32(crc).copyInto(e, 28)
        return OtaData.Entry(e)
    }
    private val empty = OtaData.Entry(ByteArray(32) { 0xFF.toByte() })

    @Test fun crcMatchesPythonBinasciiReference() {
        // binascii.crc32(struct.pack('<I', seq), 0xFFFFFFFF), as used by ESP-IDF otatool.py
        assertEquals(0x4743989aL, OtaData.seqCrc(1))
        assertEquals(0x55f63774L, OtaData.seqCrc(2))
        assertEquals(0xed4a5011L, OtaData.seqCrc(3))
        assertEquals(0xafe6a860L, OtaData.seqCrc(16))
    }

    @Test fun activeCopyIsHighestValidSequence() {
        assertEquals(1, OtaData.activeIndex(listOf(entry(3), entry(4))))
        assertEquals(1, OtaData.bootSlot(listOf(entry(3), entry(4)), 2)) // seq 4 -> slot 1
        assertEquals(0, OtaData.activeIndex(listOf(entry(5), entry(4, crc = 0))))
        assertEquals(-1, OtaData.activeIndex(listOf(empty, empty)))
        assertNull(OtaData.bootSlot(listOf(empty, empty), 2))
        assertEquals(0, OtaData.activeIndex(listOf(entry(2), entry(9, OtaData.STATE_ABORTED))))
    }

    @Test fun sequenceComputationMatchesEspIdf() {
        assertEquals(2L, OtaData.computeSeq(1, 1, 2))
        assertEquals(3L, OtaData.computeSeq(2, 0, 2))
        assertEquals(4L, OtaData.computeSeq(3, 1, 2))
        assertEquals(6L, OtaData.computeSeq(5, 1, 2))
    }

    @Test fun updateWritesInactiveCopyOnly() {
        val current = listOf(entry(1), empty)
        val u = OtaData.planUpdate(current, 1, 2)
        assertEquals(1, u.sector)
        assertEquals(2L, u.seq)
        val after = listOf(current[0], OtaData.Entry(u.entry))
        assertEquals(1, OtaData.bootSlot(after, 2))
        assertEquals(OtaData.STATE_NEW, after[1].state)
        assertEquals(4096, u.sectorImage().size)
    }

    @Test fun updateFromEmptyOtadataUsesSectorZero() {
        val u = OtaData.planUpdate(listOf(empty, empty), 1, 2)
        assertEquals(0, u.sector); assertEquals(2L, u.seq)
    }

    @Test fun bootCheckInterpretation() {
        val base = entry(1)
        assertEquals(OtaData.BootCheck.CONFIRMED, OtaData.checkAfterBoot(listOf(base, entry(2, OtaData.STATE_VALID)), 1, 2, 2))
        assertEquals(OtaData.BootCheck.RUNNING_UNCONFIRMED, OtaData.checkAfterBoot(listOf(base, entry(2, OtaData.STATE_PENDING_VERIFY)), 1, 2, 2))
        assertEquals(OtaData.BootCheck.ROLLED_BACK, OtaData.checkAfterBoot(listOf(base, entry(2, OtaData.STATE_ABORTED)), 1, 2, 2))
        assertEquals(OtaData.BootCheck.NO_ROLLBACK_INFO, OtaData.checkAfterBoot(listOf(base, entry(2, OtaData.STATE_NEW)), 1, 2, 2))
        assertEquals(OtaData.BootCheck.NOT_SELECTED, OtaData.checkAfterBoot(listOf(base, empty), 1, 2, 2))
    }
}
