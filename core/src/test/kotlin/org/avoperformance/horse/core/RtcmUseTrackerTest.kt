package org.avoperformance.horse.core

import org.avoperformance.horse.core.telemetry.RtcmUseTracker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RtcmUseTrackerTest {
    @Test fun ageFromCounterIncreases() {
        val t = RtcmUseTracker()
        t.update(4139, 1_000)
        assertNull(t.ageMs(1_500))            // first sample: no increase seen yet
        t.update(4139, 1_500)
        assertNull(t.ageMs(2_000))
        t.update(4142, 2_000)
        assertEquals(0L, t.ageMs(2_000))
        assertEquals(3_000L, t.ageMs(5_000))  // counter stopped: the age keeps growing
        t.update(4142, 5_000)
        assertEquals(3_500L, t.ageMs(5_500))
    }

    @Test fun counterResetClearsAge() {
        val t = RtcmUseTracker()
        t.update(10, 0); t.update(12, 500)
        assertEquals(0L, t.ageMs(500))
        t.update(0, 1_000)                    // back unit rebooted
        assertNull(t.ageMs(1_000))
        t.update(3, 1_500)
        assertEquals(0L, t.ageMs(1_500))
    }
}
