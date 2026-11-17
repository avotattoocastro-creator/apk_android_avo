package org.avoperformance.horse.core.rtcm

import org.avoperformance.horse.core.bytes.Crc

/** One complete RTCM3 frame (0xD3 | 6 bits 0 | 10-bit length | payload | CRC-24Q). Bytes are never altered. */
class RtcmFrame(val bytes: ByteArray) {
    val messageType: Int get() = if (bytes.size >= 5) ((bytes[3].toInt() and 0xFF) shl 4) or ((bytes[4].toInt() and 0xFF) ushr 4) else 0
    val size get() = bytes.size
}

data class RtcmStats(
    val bytesIn: Long = 0, val framesOk: Long = 0, val framesBadCrc: Long = 0, val garbageBytes: Long = 0,
    val lastType: Int = 0, val typeCounts: Map<Int, Long> = emptyMap(),
)

/**
 * Splits the NTRIP byte stream into RTCM3 frames so that BLE writes carry
 * whole frames (the watch drops a whole BLE message when its buffer is full;
 * keeping frames whole means a drop never corrupts a neighbouring frame).
 * Non-RTCM bytes (e.g. an HTTP error page) are counted and discarded, never forwarded.
 */
class RtcmFramer(private val maxBuffer: Int = 8192) {
    private var buf = ByteArray(maxBuffer + 1100)
    private var have = 0
    var stats = RtcmStats(); private set
    private val counts = HashMap<Int, Long>()

    fun feed(d: ByteArray, off: Int = 0, len: Int = d.size - off): List<RtcmFrame> {
        val out = ArrayList<RtcmFrame>()
        var o = off
        var n = len
        stats = stats.copy(bytesIn = stats.bytesIn + len)
        while (n > 0) {
            val k = minOf(n, buf.size - have)
            System.arraycopy(d, o, buf, have, k)
            have += k; o += k; n -= k
            scan(out)
            if (have == buf.size) { // cannot happen with valid frames (max 1029 B); defensive
                stats = stats.copy(garbageBytes = stats.garbageBytes + 1)
                System.arraycopy(buf, 1, buf, 0, have - 1); have--
            }
        }
        return out
    }

    private fun scan(out: MutableList<RtcmFrame>) {
        var pos = 0
        var garbage = 0L
        var ok = 0L
        var bad = 0L
        while (true) {
            while (pos < have && (buf[pos].toInt() and 0xFF) != 0xD3) { pos++; garbage++ }
            if (have - pos < 3) break
            if ((buf[pos + 1].toInt() and 0xFC) != 0) { pos++; garbage++; continue }
            val len = ((buf[pos + 1].toInt() and 0x03) shl 8) or (buf[pos + 2].toInt() and 0xFF)
            val total = len + 6
            if (have - pos < total) break
            val crc = Crc.crc24q(buf, pos, 3 + len)
            val want = ((buf[pos + 3 + len].toInt() and 0xFF) shl 16) or ((buf[pos + 4 + len].toInt() and 0xFF) shl 8) or (buf[pos + 5 + len].toInt() and 0xFF)
            if (crc == want) {
                val f = RtcmFrame(buf.copyOfRange(pos, pos + total))
                out += f
                ok++
                counts[f.messageType] = (counts[f.messageType] ?: 0) + 1
                stats = stats.copy(lastType = f.messageType)
                pos += total
            } else { bad++; pos++; garbage++ }
        }
        if (pos > 0) { System.arraycopy(buf, pos, buf, 0, have - pos); have -= pos }
        stats = stats.copy(framesOk = stats.framesOk + ok, framesBadCrc = stats.framesBadCrc + bad, garbageBytes = stats.garbageBytes + garbage, typeCounts = HashMap(counts))
    }

    companion object {
        fun build(payload: ByteArray): ByteArray {
            require(payload.size <= 1023)
            val f = ByteArray(payload.size + 6)
            f[0] = 0xD3.toByte(); f[1] = ((payload.size shr 8) and 3).toByte(); f[2] = payload.size.toByte()
            System.arraycopy(payload, 0, f, 3, payload.size)
            val c = Crc.crc24q(f, 0, 3 + payload.size)
            f[3 + payload.size] = (c shr 16).toByte(); f[4 + payload.size] = (c shr 8).toByte(); f[5 + payload.size] = c.toByte()
            return f
        }
    }
}

/**
 * Pacing of RTCM towards the watch (pure logic, no I/O).
 *  - Each BLE write carries u32 seq + up to [maxChunk] bytes; frames longer than
 *    one write are split across consecutive writes (the watch reassembles the
 *    byte stream by order; it only drops a whole write when its 16 KB buffer is full).
 *  - Credit-based flow control from RTCM_ACK (watch free space every 500 ms):
 *    we never send more than the last reported free space minus what we sent
 *    since that report.
 *  - Corrections older than [maxAgeMs] are useless for RTK: they are discarded
 *    and COUNTED (no silent loss).
 */
class RtcmPacer(var maxChunk: Int, private val maxAgeMs: Long = 5000, private val maxQueuedBytes: Int = 32 * 1024) {
    private data class Item(val frame: ByteArray, val tMs: Long)
    private val q = ArrayDeque<Item>()
    private var queuedBytes = 0
    private var credit: Long = 4096            // initial optimistic credit until the first RTCM_ACK
    private var sentSinceAck: Long = 0
    var nextSeq: Long = 1; private set
    var droppedStaleBytes = 0L; private set
    var droppedOverflowBytes = 0L; private set
    var sentBytes = 0L; private set
    var sentWrites = 0L; private set
    var watchReportedDropped = 0L; private set
    var watchExpectedSeq = 0L; private set
    var lastAckMs = 0L; private set

    fun offer(frame: RtcmFrame, nowMs: Long) {
        q.addLast(Item(frame.bytes, nowMs))
        queuedBytes += frame.size
        while (queuedBytes > maxQueuedBytes && q.isNotEmpty()) {
            val it = q.removeFirst(); queuedBytes -= it.frame.size; droppedOverflowBytes += it.frame.size
        }
    }

    fun onAck(freeBytes: Long, expectedSeq: Long, watchDropped: Long, nowMs: Long) {
        credit = freeBytes
        sentSinceAck = 0
        watchExpectedSeq = expectedSeq
        watchReportedDropped = watchDropped
        lastAckMs = nowMs
    }

    /** Next chunk to write (seq, bytes) or null when nothing can be sent now. Call [onSent] after a successful write. */
    fun next(nowMs: Long): Pair<Long, ByteArray>? {
        while (q.isNotEmpty() && nowMs - q.first().tMs > maxAgeMs) {
            val it = q.removeFirst(); queuedBytes -= it.frame.size; droppedStaleBytes += it.frame.size
        }
        if (q.isEmpty()) return null
        // gather whole frames up to maxChunk; a frame bigger than maxChunk is sent in pieces
        val first = q.first()
        val budget = credit - sentSinceAck
        if (budget < minOf(first.frame.size, maxChunk)) return null
        val out = java.io.ByteArrayOutputStream()
        if (first.frame.size > maxChunk) {
            out.write(first.frame, 0, maxChunk)
            return Pair(nextSeq, out.toByteArray())
        }
        for (it in q) {
            if (out.size() + it.frame.size > maxChunk || out.size() + it.frame.size > budget) break
            out.write(it.frame)
        }
        return Pair(nextSeq, out.toByteArray())
    }

    /** Commit [n] bytes as written. */
    fun onSent(n: Int) {
        var left = n
        while (left > 0 && q.isNotEmpty()) {
            val head = q.first()
            if (head.frame.size <= left) {
                q.removeFirst(); queuedBytes -= head.frame.size; left -= head.frame.size
            } else {
                // partial frame (frame larger than one write): keep the remainder at the head
                q.removeFirst()
                val rest = head.frame.copyOfRange(left, head.frame.size)
                q.addFirst(Item(rest, head.tMs))
                queuedBytes -= left
                left = 0
            }
        }
        sentSinceAck += n
        sentBytes += n
        sentWrites++
        nextSeq++
    }

    fun queued() = queuedBytes
    fun clear() { q.clear(); queuedBytes = 0 }
    /** After a reconnection the watch restarts its sequence tracking; credit restarts too. */
    fun onReconnect() { credit = 4096; sentSinceAck = 0 }
}
