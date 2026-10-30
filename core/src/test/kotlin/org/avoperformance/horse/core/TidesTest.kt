package org.avoperformance.horse.core

import org.avoperformance.horse.core.tide.*
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class TidesTest {
    private val h = 3_600_000L
    private val ext = listOf(
        TideExtreme(0, 0.9, false), TideExtreme(6 * h, 4.5, true),
        TideExtreme(12 * h, 1.0, false), TideExtreme(18 * h, 4.3, true), TideExtreme(24 * h, 1.1, false)
    )

    @Test fun cosineCurvePassesThroughExtremesAndMidpoint() {
        assertEquals(2.7, TideMath.levelAt(ext, 3 * h)!!.heightM, 1e-9)
        assertTrue(TideMath.levelAt(ext, 3 * h)!!.rising)
        assertFalse(TideMath.levelAt(ext, 7 * h)!!.rising)
        assertEquals(4.5, TideMath.levelAt(ext, 6 * h + 1)!!.heightM, 1e-3)
        assertNull(TideMath.levelAt(ext, -1)) // nothing invented before the first official extreme
    }

    @Test fun coefficientsScaleWithRange() {
        val mean = TideMath.meanRange(ext)!!
        val c = TideMath.withCoefficients(ext, mean)
        assertEquals(3.4, mean, 1e-9)
        assertEquals(73, c[1].coefficient)
        assertEquals(67, c[3].coefficient)
        assertTrue(c[1].coefficient!! > c[3].coefficient!!)
        assertNull(c[0].coefficient)
        assertEquals("Mareas vivas", TideMath.coefficientLabel(72))
    }

    @Test fun sunriseSantander() {
        val day = Instant.parse("2026-10-23T12:00:00Z").toEpochMilli()
        val s = Astro.sun(day, 43.46, -3.80)
        val rise = Instant.ofEpochMilli(s.riseMs!!).atOffset(ZoneOffset.UTC)
        val set = Instant.ofEpochMilli(s.setMs!!).atOffset(ZoneOffset.UTC)
        assertEquals(6 * 60 + 39.0, rise.hour * 60.0 + rise.minute, 3.0) // ≈ 08:39 CEST
        assertEquals(17 * 60 + 21.0, set.hour * 60.0 + set.minute, 3.0) // ≈ 19:21 CEST
    }

    @Test fun moonPhaseAndRiseSet() {
        val full = Instant.parse("2026-10-26T04:12:00Z").toEpochMilli()
        assertEquals(MoonPhase.FULL, Astro.moon(full).phase)
        assertTrue(Astro.moon(full).illumination >= 98)
        // At full moon the moon rises near sunset and sets near sunrise.
        val (rise, set) = Astro.moonRiseSet(Instant.parse("2026-10-26T00:00:00Z").toEpochMilli(), 43.46, -3.80)
        assertNotNull(rise); assertNotNull(set)
        val riseH = Instant.ofEpochMilli(rise!!).atOffset(ZoneOffset.UTC).hour
        val setH = Instant.ofEpochMilli(set!!).atOffset(ZoneOffset.UTC).hour
        assertTrue("rise $riseH", riseH in 16..19)
        assertTrue("set $setH", setH in 5..9)
    }
}
