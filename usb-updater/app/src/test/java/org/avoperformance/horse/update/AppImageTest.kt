package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test

class AppImageTest {
    private val image = TestImages.build("3.7.1-rc2", "AVO-CHEST", 300_000)

    @Test fun validImageParsed() {
        val info = AppImage.parse(image)
        assertEquals("AVO-CHEST 3.7.1-rc2", info.label)
        assertEquals(2, info.segments.size)
        assertTrue(info.hashAppended)
        assertEquals("16 MB", info.flashSizeText)
        val r = FirmwareImage.inspect(image.inputStream())
        assertTrue(r.reason, r.validHeader)
        assertEquals(9, r.chipId)
    }

    private fun rejects(b: ByteArray) {
        val e = assertThrows(UpdateException::class.java) { AppImage.parse(b) }
        assertEquals(Failure.INCOMPATIBLE, e.failure)
    }

    @Test fun corruptByteRejected() = rejects(image.copyOf().also { it[5000] = (it[5000] + 1).toByte() })
    @Test fun truncatedRejected() = rejects(image.copyOf(image.size - 40))
    @Test fun trailingDataRejected() = rejects(image + ByteArray(16))
    @Test fun wrongChipRejected() = rejects(image.copyOf().also { it[12] = 5 })
    @Test fun badMagicRejected() = rejects(image.copyOf().also { it[0] = 0 })
    @Test fun badShaRejected() = rejects(image.copyOf().also { it[it.size - 1] = (it[it.size - 1] + 1).toByte() })

    @Test fun legacyValidatorStillWorks() {
        assertTrue(ImageSegments.validate(image).contains("checksum correcto"))
        assertThrows(IllegalArgumentException::class.java) { ImageSegments.validate(image.copyOf(100)) }
    }
}
