package org.avoperformance.horse.core

import org.avoperformance.horse.core.rtcm.RtcmFrame
import org.avoperformance.horse.core.rtcm.RtcmFramer
import org.avoperformance.horse.core.rtcm.RtcmPacer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.Random

class RtcmTest {
    private fun frames(n: Int, seed: Long): List<ByteArray> {
        val r = Random(seed)
        return (0 until n).map { i ->
            val len = 8 + r.nextInt(if (i % 7 == 0) 1000 else 200)
            val p = ByteArray(len).also { r.nextBytes(it) }
            val type = listOf(1005, 1077, 1087, 1097, 1127, 1230)[i % 6]
            p[0] = (type shr 4).toByte(); p[1] = (((type and 0xF) shl 4) or (p[1].toInt() and 0x0F)).toByte()
            RtcmFramer.build(p)
        }
    }

    @Test fun framerSurvivesArbitrarySplitsAndGarbage() {
        val fs = frames(300, 1)
        val stream = ByteArrayOutputStream()
        val garbage = "HTTP/1.1 garbage\r\n".toByteArray()
        for ((i, f) in fs.withIndex()) { if (i % 50 == 0) stream.write(garbage); stream.write(f) }
        val all = stream.toByteArray()
        val r = Random(2)
        val fr = RtcmFramer()
        val got = ArrayList<RtcmFrame>()
        var o = 0
        while (o < all.size) { val n = minOf(all.size - o, 1 + r.nextInt(700)); got += fr.feed(all, o, n); o += n }
        assertEquals(fs.size, got.size)
        for (i in fs.indices) assertArrayEquals(fs[i], got[i].bytes)
        assertEquals(fs.size.toLong(), fr.stats.framesOk)
        assertTrue(fr.stats.garbageBytes >= 6L * garbage.size)
        assertEquals(all.size.toLong(), fr.stats.bytesIn)
        assertEquals(50L, fr.stats.typeCounts[1005])
    }

    @Test fun corruptedFrameIsCountedNotForwarded() {
        val fs = frames(3, 3)
        val bad = fs[1].copyOf(); bad[10] = (bad[10].toInt() xor 0x55).toByte()
        val fr = RtcmFramer()
        val got = fr.feed(fs[0] + bad + fs[2])
        assertEquals(2, got.size)
        assertArrayEquals(fs[0], got[0].bytes); assertArrayEquals(fs[2], got[1].bytes)
        assertEquals(1L, fr.stats.framesBadCrc)
    }

    /** Simulates the watch buffer (16 KB, all-or-nothing per write) and checks the byte stream arrives intact and in order. */
    @Test fun pacerRespectsCreditAndReconstructsStream() {
        val fs = frames(400, 4)
        val maxChunk = 228   // MTU 247 → 244 − 12 − 4
        val pacer = RtcmPacer(maxChunk, maxAgeMs = 600_000, maxQueuedBytes = 1 shl 20)
        val watchCap = 16 * 1024
        var watchUsed = 0
        val received = ByteArrayOutputStream()
        var watchDropped = 0L
        var lastSeq = 0L
        var now = 0L
        var fi = 0
        var watchDrain: Int
        while (fi < fs.size || pacer.queued() > 0) {
            // NTRIP burst: 4 frames every 2 ms (faster than the watch can forward)
            repeat(4) { if (fi < fs.size) pacer.offer(RtcmFrame(fs[fi++]), now) }
            // the watch forwards 100 B per 2 ms to the receiver → its 16 KB buffer would overflow without credit
            watchDrain = minOf(watchUsed, 100); watchUsed -= watchDrain
            // ACK every 500 ms
            if (now % 500 == 0L) pacer.onAck((watchCap - watchUsed).toLong(), lastSeq + 1, watchDropped, now)
            while (true) {
                val (seq, data) = pacer.next(now) ?: break
                assertTrue(data.size <= maxChunk)
                assertEquals(lastSeq + 1, seq)
                if (watchUsed + data.size > watchCap) { watchDropped += data.size } else { watchUsed += data.size; received.write(data) }
                lastSeq = seq
                pacer.onSent(data.size)
            }
            now += 2
        }
        assertEquals(0L, watchDropped)   // credit-based pacing never overflows the watch
        val expect = ByteArrayOutputStream().also { s -> fs.forEach { s.write(it) } }.toByteArray()
        assertArrayEquals(expect, received.toByteArray())
        assertEquals(expect.size.toLong(), pacer.sentBytes)
        assertEquals(0L, pacer.droppedStaleBytes)
    }

    @Test fun staleCorrectionsAreDroppedAndCounted() {
        val fs = frames(5, 5)
        val p = RtcmPacer(228, maxAgeMs = 5000)
        p.onAck(0, 1, 0, 0)          // watch full: nothing can be sent
        fs.forEach { p.offer(RtcmFrame(it), 0) }
        assertEquals(null, p.next(1000))
        assertEquals(null, p.next(6000))
        assertEquals(fs.sumOf { it.size }.toLong(), p.droppedStaleBytes)
        assertEquals(0, p.queued())
    }

    @Test fun bigFrameIsSplitAcrossWrites() {
        val big = RtcmFramer.build(ByteArray(1000) { it.toByte() })
        val p = RtcmPacer(228)
        p.onAck(16384, 1, 0, 0)
        p.offer(RtcmFrame(big), 0)
        val out = ByteArrayOutputStream()
        var writes = 0
        while (true) { val (_, d) = p.next(1) ?: break; out.write(d); p.onSent(d.size); writes++ }
        assertArrayEquals(big, out.toByteArray())
        assertEquals((big.size + 227) / 228, writes)
    }
}
