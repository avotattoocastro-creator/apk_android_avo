package org.avoperformance.horse.core

import org.avoperformance.horse.core.ble.TelemetryV3
import org.junit.Assert.assertEquals
import org.junit.Test

/** BACK 3.13.12 packs two counters into quality_mon (bits 4-5 re-requests, bits 6-7 receiver re-detections). */
class QualityMonBitsTest {
    private fun v3(mon: Int) = TelemetryV3(3, 30, 25, 40, 30, 0, 6, 10, 5, 10, 36, 25, 49, 1, mon, 0, 0xFFFF, 0, 0, 450, 117)

    @Test fun oldBackKeepsState() {
        val q = v3(2)
        assertEquals(2, q.monitorState); assertEquals(0, q.monitorRearms); assertEquals(0, q.receiverResets)
    }

    @Test fun countersFromBack31312() {
        val q = v3(1 or (1 shl 4) or (3 shl 6))   // OK, re-asked once, receiver re-detected 3+ times
        assertEquals(1, q.monitorState); assertEquals(1, q.monitorRearms); assertEquals(3, q.receiverResets)
        assertEquals(6, v3(6 or (3 shl 4)).monitorState)
    }
}
