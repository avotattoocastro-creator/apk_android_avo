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
        // presencia: en cuanto llega TELEMETRY (pecho encendido), aunque no grabe
        val first = r.onTelemetry(tel(WatchSessionState.IDLE), 0)
        val sid = (first[0] as LiveAction.Start).sid
        assertEquals(LiveAction.State(sid, "IDLE"), first[1])
        assertTrue(first[2] is LiveAction.Last)
        // en espera: 1 muestra por segundo aunque el pecho mande 2 Hz
        assertEquals(0, r.onTelemetry(tel(WatchSessionState.IDLE), 500).count { it is LiveAction.Last })
        assertEquals(1, r.onTelemetry(tel(WatchSessionState.IDLE), 1_000).count { it is LiveAction.Last })
        // entra en la geocerca: graba (2 Hz)
        val rec = r.onTelemetry(tel(WatchSessionState.RECORDING), 1_500)
        assertTrue(rec.any { it is LiveAction.State && it.state == "REC" })
        assertEquals("LIVE1,1500,", (rec.first { it is LiveAction.Last } as LiveAction.Last).line.substring(0, 11))
        var lasts = 0
        for (i in 1..20) lasts += r.onTelemetry(tel(WatchSessionState.RECORDING), 1_500 + i * 500L).count { it is LiveAction.Last }
        assertEquals(20, lasts)
        val p = r.onTelemetry(tel(WatchSessionState.PAUSED), 12_000)
        assertTrue(p.any { it is LiveAction.State && it.state == "PAUSE" })
        // sale de la geocerca: el directo sigue, en espera
        val idle = r.onTelemetry(tel(WatchSessionState.STOPPED_WAITING_UPLOAD), 13_000)
        assertTrue(idle.any { it is LiveAction.State && it.state == "IDLE" })
        assertEquals(sid, r.activeSessionId)
        // pecho apagado o fuera de alcance: termina tras 60 s sin TELEMETRY
        assertEquals(0, r.onTick(60_000).size)
        val end = r.onTick(73_001)
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
