package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class FlashReaderTest {
    @Test fun parsesBundledEspressifStub() {
        val json = File("src/main/assets/stub/esp32s3.json").readText()
        val s = StubImage.parse(json)
        assertEquals(1077384616L, s.entry)
        assertEquals(1077379072L, s.textStart)
        assertEquals(8668, s.text.size)
        assertEquals(264, s.data!!.size)
        assertEquals(1070280132L, s.dataStart)
    }

    @Test fun findsImageEndAndIdentityStrings() {
        val img = TestImages.build("3.7.2-rc1")
        val padded = img + ByteArray(8192) { 0xFF.toByte() }
        assertEquals(img.size, FirmwareFingerprint.imageLength(padded))
        val r = FirmwareFingerprint.analyse(padded)
        assertNotNull(r.info)
        assertEquals(img.size, r.imageBytes)
    }

    @Test fun rejectsNonImage() {
        assertNull(FirmwareFingerprint.imageLength(ByteArray(64) { 0xFF.toByte() }))
    }

    private fun reader(fake: FakeEsp32S3) = FlashReader(fake.port, object : FlashReader.Listener {
        override fun onProgress(text: String, percent: Int?) {}
        override fun onLog(line: String) {}
    }, clock = fake.clock, stubJson = { File("src/main/assets/stub/esp32s3.json").readText() })

    @Test fun identifiesModuleAndReadsWithStub() {
        val fake = TestImages.watch("3.6.0")
        val r = reader(fake)
        val s = r.connect(autoBootloader = false)
        assertTrue(s.info.bootloaderValid)
        assertTrue(s.info.partitions.isNotEmpty())
        val boot = s.info.bootPartition!!
        assertEquals(0x10000L, boot.offset)
        assertTrue(s.info.apps.first { it.partition == boot }.version.contains("3.6.0"))
        // read 300 KB of the running slot through the stub, MD5 checked per piece
        val out = java.io.ByteArrayOutputStream()
        val sha = r.read(s, boot.offset, 300_000, out, "test")
        assertTrue(fake.stubRunning)
        assertEquals(emptyList<String>(), fake.ackErrors)
        assertArrayEquals(fake.region(boot.offset, 300_000), out.toByteArray())
        assertEquals(hex(java.security.MessageDigest.getInstance("SHA-256").digest(out.toByteArray())), sha)
        val fp = FirmwareFingerprint.analyse(out.toByteArray())
        assertTrue(fp.info?.version?.contains("3.6.0") == true)
        r.finish(s)
    }

    @Test fun readerNeverWritesFlash() {
        val fake = TestImages.watch()
        val before = fake.flash.copyOf()
        val r = reader(fake)
        val s = r.connect(false)
        r.read(s, 0, 0x20000, java.io.ByteArrayOutputStream(), "x")
        assertTrue(fake.erasedRegions.isEmpty() && fake.writeRanges.isEmpty())
        assertArrayEquals(before, fake.flash)
    }
}
