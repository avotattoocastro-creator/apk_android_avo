package org.avoperformance.horse.core

import org.avoperformance.horse.core.geo.GeoPoint
import org.avoperformance.horse.core.raw.CadenceEstimator
import org.avoperformance.horse.core.raw.EventKind
import org.avoperformance.horse.core.raw.Gait
import org.avoperformance.horse.core.raw.RawScan
import org.avoperformance.horse.core.raw.TrackPoint
import org.avoperformance.horse.core.raw.TrainingAnalysis
import org.avoperformance.horse.core.raw.TrainingInsights
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class InsightsTest {
    private val scan = RawScan(null, 0, 0, 0, 0, 0, 0, true, false, 0)

    /** Straight line northwards at 10 Hz with the given speed profile (m/s) and altitude profile. */
    private fun track(speeds: List<Double>, alt: (Int) -> Double = { 10.0 }): List<TrackPoint> {
        var lat = 43.4
        return speeds.mapIndexed { i, v ->
            if (i > 0) lat += v * 0.1 / 111_195.0
            TrackPoint(GeoPoint.of(lat, -3.42), 100_000L + i * 100L, v, 2, 0.02, alt(i), 0.03, 24, 1_000_000L + i * 100_000L)
        }
    }

    private fun analysis(t: List<TrackPoint>, markers: List<Long> = emptyList()) =
        TrainingAnalysis(scan, t.size, t.size, 0, 0, 0, t.size, 0.0, t.maxOf { it.speedMs }, null, null, 10, 0, 0, markers.size, 0, t, markers)

    @Test fun cadenceFromSyntheticImuIsScaleFree() {
        for ((spm, scale) in listOf(100.0 to 1.0, 150.0 to 4000.0, 60.0 to 0.01)) {
            val est = CadenceEstimator()
            val f = spm / 60.0
            var us = 0L
            repeat(200 * 20) { // 20 s at 200 Hz
                est.add(us, scale * (1000 + 300 * sin(2 * PI * f * us / 1e6)))
                us += 5_000
            }
            val r = est.result()
            assertTrue("estimates for $spm", r.size >= 5)
            r.forEach { assertEquals("spm $spm", spm, it.spm, spm * 0.03) }
        }
    }

    @Test fun noCadenceWhenStanding() {
        val est = CadenceEstimator()
        var us = 0L
        repeat(200 * 20) { est.add(us, 1000.0 + (it % 3)); us += 5_000 }
        assertTrue(est.result().isEmpty())
    }

    @Test fun gaitAccelerationEffortsAndSplits() {
        // 60 s walk (1.5 m/s), 30 s gallop (8 m/s), 60 s trot (3.5 m/s) at 10 Hz
        val speeds = List(600) { 1.5 } + List(300) { 8.0 } + List(600) { 3.5 }
        val a = analysis(track(speeds), markers = listOf(1_000_000L + 700 * 100_000L))
        val ins = TrainingInsights.compute(a)
        assertEquals(60.0, ins.gaitSeconds[Gait.WALK]!!, 0.5)
        assertEquals(30.0, ins.gaitSeconds[Gait.GALLOP]!!, 0.5)
        assertEquals(60.0, ins.gaitSeconds[Gait.TROT]!!, 0.5)
        // step 1.5 -> 8 m/s in 0.1 s is above the 12 m/s² spike limit: ignored, not reported as 6.6 g
        assertNull(ins.maxAccelG)
        val total = 60 * 1.5 + 30 * 8.0 + 60 * 3.5
        assertEquals(total, ins.distM.last(), total * 0.01)
        val fastest = ins.efforts.first()
        assertEquals(8.0, fastest.avgSpeedMs, 0.05)
        assertEquals(30.0, fastest.durationS, 0.3)
        assertEquals(250.0, ins.splitUnitM, 0.0) // 540 m in total
        assertEquals(2, ins.splits.size) // 250 + 250 m; the last 40 m are under 30 % of a split
        assertEquals(250.0, ins.splits[1].fromM, 1.0); assertTrue(ins.splits.all { it.avgSpeedMs > 0.0 })
        val kinds = ins.events.map { it.kind }
        assertEquals(EventKind.START, kinds.first()); assertEquals(EventKind.FINISH, kinds.last())
        assertTrue(EventKind.FIRST_GALLOP in kinds); assertTrue(EventKind.MARKER in kinds)
        assertEquals(70.0, ins.events.first { it.kind == EventKind.MARKER }.timeS, 0.2)
    }

    @Test fun smoothAccelerationInG() {
        val speeds = List(100) { i -> i * 0.098 } // +0.98 m/s² = 0.1 g
        val ins = TrainingInsights.compute(analysis(track(speeds)))
        assertEquals(0.1, ins.maxAccelG!!, 0.005)
    }

    @Test fun altitudeGainAndSlope() {
        // 3 m/s for 100 s = 300 m, climbing 30 m linearly -> 10 % grade
        val ins = TrainingInsights.compute(analysis(track(List(1000) { 3.0 }) { i -> 10.0 + 30.0 * i / 999 }))
        assertEquals(30.0, ins.gainM!!, 1.5)
        assertEquals(0.0, ins.lossM!!, 0.01)
        assertEquals(10.0, ins.slopeMaxPct!!, 0.6)
        assertEquals(10.0, ins.slopeMeanAbsPct!!, 0.6)
    }

    @Test fun noAltitudeMeansNoInventedValues() {
        val ins = TrainingInsights.compute(analysis(track(List(200) { 3.0 }) { Double.NaN }))
        assertNull(ins.altMaxM); assertNull(ins.gainM); assertNull(ins.slopeMaxPct)
        assertNull(ins.cadenceMax)
    }
}
