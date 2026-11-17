package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test

class OtaPlanTest {
    private fun part(name: String, type: Int, subtype: Int, offset: Long, size: Long) =
        PartitionTable.Entry(name, type, subtype, offset, size, 0)
    private val table = PartitionTable.Result(listOf(
        part("nvs", 1, 2, 0x9000, 0x5000),
        part("otadata", 1, 0, 0xE000, 0x2000),
        part("app0", 0, 0x10, 0x10000, 0x600000),
        part("app1", 0, 0x11, 0x610000, 0x600000)
    ), true)
    private val firmware = FirmwareImage.Result(1364544, "test", true, 9, "ok")
    private fun state(active: Int?, verified: Boolean = true, encryption: Boolean? = true, secureBoot: Boolean? = true) =
        OtaPlan.DeviceState(active, verified, encryption, secureBoot, 0x1000000)

    @Test fun chooseOnlyInactiveSlot() {
        assertEquals("app1", OtaPlan.select(table, firmware, state(0x10)).target.name)
        assertEquals("app0", OtaPlan.select(table, firmware, state(0x11)).target.name)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectHistoricalTableWithoutDeviceVerification() {
        OtaPlan.select(table, firmware, state(0x10, verified = false))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectUnknownSecurity() {
        OtaPlan.select(table, firmware, state(0x10, encryption = null))
    }

    @Test(expected = IllegalStateException::class)
    fun rejectUnknownActiveSlot() {
        OtaPlan.select(table, firmware, state(null))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectOversizedFirmware() {
        OtaPlan.select(table, firmware.copy(bytes = 0x600001), state(0x10))
    }
}
