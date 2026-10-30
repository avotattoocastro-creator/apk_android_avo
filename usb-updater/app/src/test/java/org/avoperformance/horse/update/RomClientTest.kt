package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test
import java.security.MessageDigest

/** SIMULATED: ESP32-S3 ROM protocol against [FakeEsp32S3]. */
class RomClientTest {
    private fun connected(fake: FakeEsp32S3 = TestImages.watch()): Pair<FakeEsp32S3, EspRom> {
        val rom = EspRom(fake.port.open(1000), fake.clock)
        assertTrue("ROM (no stub) responde", rom.sync())
        return fake to rom
    }

    @Test fun slipStreamHandlesFragmentsNoiseAndEscapes() {
        val packet = byteArrayOf(1, 0x0A, 2, 0, 0, 0, 0, 0, 0xC0.toByte(), 0xDB.toByte())
        val encoded = "ESP-ROM:esp32s3 boot banner\r\n".toByteArray() + RomProtocol.slipEncode(packet)
        val s = RomProtocol.SlipStream()
        val frames = encoded.map { s.feed(byteArrayOf(it)) }.flatten()
        assertEquals(1, frames.size)
        assertArrayEquals(packet, frames.single())
    }

    @Test fun slipStreamResyncsAfterCorruptEscape() {
        val s = RomProtocol.SlipStream()
        val bad = byteArrayOf(0xC0.toByte(), 1, 0xDB.toByte(), 0x11, 2, 3)
        val good = RomProtocol.slipEncode(byteArrayOf(9, 9, 9))
        assertEquals(listOf(listOf<Byte>(9, 9, 9)), s.feed(bad + good).map { it.toList() })
    }

    @Test fun requestEncodingMatchesEsptoolStruct() {
        val f = RomProtocol.decodeFrames(RomProtocol.encodeRequest(0x03, byteArrayOf(1, 2, 3), 0xAB)).single()
        assertArrayEquals(byteArrayOf(0, 3, 3, 0, 0xAB.toByte(), 0, 0, 0, 1, 2, 3), f)
    }

    @Test fun syncDetectsRomAndReadsRegisters() {
        val (_, rom) = connected()
        assertEquals(4L, rom.readReg(EspRom.UARTDEV_BUF_NO))
        assertTrue(rom.usesUsbJtagSerial())
    }

    @Test fun syncFailsCleanlyWhenBootloaderSilent() {
        val fake = TestImages.watch().apply { ignoreSync = true }
        val rom = EspRom(fake.port.open(1000), fake.clock)
        val e = assertThrows(UpdateException::class.java) { rom.sync(3) }
        assertEquals(Failure.NO_BOOTLOADER, e.failure)
    }

    @Test fun securityInfoParsedWithS3Layout() {
        val fake = TestImages.watch().apply { securityFlags = 1; cryptCnt = 1 }
        val (_, rom) = connected(fake)
        val s = rom.securityInfo()
        assertEquals(9L, s.chipId)
        assertTrue(s.secureBoot)
        assertTrue(s.flashEncryption)
    }

    @Test fun romErrorStatusIsReported() {
        val (_, rom) = connected()
        // FLASH_BEGIN before SPI_ATTACH -> ROM error 0x05
        val e = assertThrows(UpdateException::class.java) { rom.flashBegin(0x610000, 4096) }
        assertEquals(Failure.ROM_ERROR, e.failure)
    }

    @Test fun lostRepliesAreRetried() {
        val (fake, rom) = connected()
        fake.dropEveryNthReply = 3
        repeat(10) { assertEquals(4L, rom.readReg(EspRom.UARTDEV_BUF_NO)) }
    }

    @Test fun timeoutWhenNoReply() {
        val (fake, rom) = connected()
        fake.dropEveryNthReply = 1
        val start = fake.clock.now
        val e = assertThrows(UpdateException::class.java) { rom.readReg(EspRom.UARTDEV_BUF_NO) }
        assertEquals(Failure.NO_BOOTLOADER, e.failure)
        assertTrue(fake.clock.now - start >= 9000)
    }

    @Test fun flashReadsAreRealAndMd5Verified() {
        val (fake, rom) = connected()
        DeviceProbe.prepare(rom)
        assertEquals(Triple(0xC8, 0x40, 0x19), rom.flashJedec())
        val data = rom.readFlashVerified(0x9000, 300)
        assertArrayEquals(fake.region(0x9000, 300), data)
        assertEquals(hex(MessageDigest.getInstance("MD5").digest(data)), rom.flashMd5(0x9000, 300))
    }

    @Test fun badFastReadFallsBackToWordReads() {
        val fake = TestImages.watch().apply { corruptSpiReadsWithChunk64 = true }
        val (_, rom) = connected(fake)
        DeviceProbe.prepare(rom)
        assertArrayEquals(fake.region(0x8000, 96), rom.readFlashVerified(0x8000, 96))
    }

    @Test fun jedecCapacityTable() {
        assertEquals(16L shl 20, DeviceProbe.flashSizeFromJedec(0xEF, 0x18))
        assertEquals(32L shl 20, DeviceProbe.flashSizeFromJedec(0xC8, 0x19))
        assertEquals(4L shl 20, DeviceProbe.flashSizeFromJedec(0x1F, 0x07))
        assertNull(DeviceProbe.flashSizeFromJedec(0xC8, 0x00))
    }

    @Test fun flashCommandFormatsForS3() {
        val begin = FlashCommands.beginPayload(0x610000, 1364544)
        assertEquals(20, begin.size)
        assertEquals(1364544L, u32le(begin, 0))
        assertEquals(1333L, u32le(begin, 4))
        assertEquals(0x400L, u32le(begin, 8))
        assertEquals(0x610000L, u32le(begin, 12))
        assertEquals(0L, u32le(begin, 16))
        assertEquals(8, FlashCommands.spiAttachPayload().size)
        assertEquals(24, FlashCommands.spiSetParamsPayload(16L shl 20).size)
        assertThrows(IllegalArgumentException::class.java) { FlashCommands.beginPayload(0x610800, 10) }
        assertThrows(IllegalArgumentException::class.java) { FlashCommands.dataPayload(0, ByteArray(1000)) }
    }
}
