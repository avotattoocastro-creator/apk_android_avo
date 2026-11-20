package org.avoperformance.horse.core

import org.avoperformance.horse.core.ble.GeofenceState
import org.avoperformance.horse.core.ble.RecStatus
import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.live.LiveAction
import org.avoperformance.horse.core.live.LiveCodec
import org.avoperformance.horse.core.live.LiveRecorder
import org.avoperformance.horse.core.live.LiveSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** LIVE1: formato de texto del directo (mismos vectores que ipad/AVOiPadTests/LiveCodecTests.swift). */
class LiveCodecTest {
    private fun tel(s: WatchSessionState, speed: Int = 15200, dist: Long = 250000) = Telemetry(
        s, GeofenceState.RECORDING, RecStatus.RECORDING, 3, 0, 31, 180, 434190000, -34540000, speed, dist, 60000, 80,
        true, false, true, 10, 0, 0, false, null,
    )

    @Test fun vectorSharedWithIpad() {
        val s = LiveSample(1500, 434190000, -34540000, 15200, 250000, 3, 0, 180, 31, 2)
        assertEquals("LIVE1,1500,434190000,-34540000,15200,250000,3,0,180,31,2", LiveCodec.encode(s))
        assertEquals(listOf(s), LiveCodec.decode(LiveCodec.encode(s)))
        val c = LiveCodec.encodeChunk(listOf(s, s.copy(tMs = 2000)))
        assertEquals("LIVE1,1500,434190000,-34540000,15200,250000,3,0,180,31,2;2000,434190000,-34540000,15200,250000,3,0,180,31,2", c)
        assertEquals(2, LiveCodec.decode(c).size)
        assertTrue(s.hasPosition)
    }

    @Test fun malformedIsDiscarded() {
        assertEquals(0, LiveCodec.decode(null).size)
        assertEquals(0, LiveCodec.decode("hola").size)
        assertEquals(1, LiveCodec.decode("LIVE1,1,2,3,4,5,6,7,8,9,10;1,2,3;x,2,3,4,5,6,7,8,9,10").size)
        assertEquals(0, LiveCodec.decode("LIVE1,1,99999999999,3,4,5,6,7,8,9,10").size)
    }

    @Test fun sessionIdIsUtc() {
        assertEquals("20261119-161500", LiveCodec.sessionId(1795104900000L))
    }

    @Test fun recorderLifecycle() {
        val r = LiveRecorder(chunkMs = 10_000)
        assertEquals(0, r.onTelemetry(tel(WatchSessionState.IDLE), 0).size)
        val first = r.onTelemetry(tel(WatchSessionState.RECORDING), 1_000)
        val sid = (first[0] as LiveAction.Start).sid
        assertTrue(first[1] is LiveAction.Last)
        assertEquals("LIVE1,0,", (first[1] as LiveAction.Last).line.substring(0, 8))
        // 2 Hz durante 10 s: un bloque
        var chunks = 0
        for (i in 1..20) chunks += r.onTelemetry(tel(WatchSessionState.RECORDING), 1_000 + i * 500L).count { it is LiveAction.Chunk }
        assertEquals(1, chunks)
        val p = r.onTelemetry(tel(WatchSessionState.PAUSED), 12_000)
        assertTrue(p.any { it is LiveAction.State && it.state == "PAUSE" })
        val end = r.onTelemetry(tel(WatchSessionState.STOPPED_WAITING_UPLOAD), 13_000)
        assertTrue(end.any { it is LiveAction.Chunk && it.index == 1 })
        assertEquals(LiveAction.End(sid), end.last())
        assertEquals(null, r.activeSessionId)
        assertEquals(0, r.finish().size)
    }

    @Test fun chunkFitsFirebaseLimit() {
        val r = LiveRecorder(chunkMs = 1_000_000, maxPerChunk = 40)
        r.onTelemetry(tel(WatchSessionState.RECORDING, speed = -2147483, dist = 4294967295L), 0)
        var max = 0
        for (i in 1..80) r.onTelemetry(tel(WatchSessionState.RECORDING, speed = -2147483, dist = 4294967295L), i.toLong())
            .filterIsInstance<LiveAction.Chunk>().forEach { max = maxOf(max, it.line.length) }
        assertTrue("bloque de $max caracteres", max in 1..LiveCodec.MAX_CHUNK)
    }
}
