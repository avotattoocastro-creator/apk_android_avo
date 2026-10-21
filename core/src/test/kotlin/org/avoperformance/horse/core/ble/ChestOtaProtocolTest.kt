package org.avoperformance.horse.core.ble

import org.junit.Assert.*
import org.junit.Test

class ChestOtaProtocolTest {
    @Test fun invalidFilesRejected() {
        assertFalse(ChestOtaProtocol.inspect(ByteArray(0)).valid)
        assertFalse(ChestOtaProtocol.inspect(ByteArray(1024)).valid)
        val wrong = ByteArray(512) { 0x42 }
        wrong[0] = 0xE9.toByte()
        assertFalse(ChestOtaProtocol.inspect(wrong).valid)
    }

    @Test fun otaPayloadsMatchFirmware() {
        val bytes = ByteArray(512)
        bytes[0] = 0xE9.toByte()
        val marker = ChestOtaProtocol.IMAGE_MARKER.toByteArray()
        marker.copyInto(bytes, 100)
        assertTrue(ChestOtaProtocol.inspect(bytes).valid)
        val begin = ChestOtaProtocol.beginPayload(bytes)
        assertEquals(36, begin.size)
        assertEquals(512L, ChestOtaProtocol.confirmedOffset(begin.copyOfRange(0,4)))
        val data = ChestOtaProtocol.dataPayload(10, bytes, 40)
        assertEquals(44, data.size)
        assertEquals(10L, ChestOtaProtocol.confirmedOffset(data.copyOfRange(0,4)))
        assertArrayEquals(bytes.copyOfRange(10,50), data.copyOfRange(4,44))
    }
}
