package org.avoperformance.horse.core.raw

import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.bytes.Crc
import org.avoperformance.horse.core.bytes.leU16
import org.avoperformance.horse.core.bytes.leU32
import org.avoperformance.horse.core.bytes.leU64
import org.avoperformance.horse.core.geo.GeoPoint
import org.avoperformance.horse.core.geo.haversineM
import java.io.InputStream

/**
 * Reader for AVO RAW FORMAT v1 segments (.avr), port of avo_raw.cpp raw_scan()
 * plus the UART frame / GNSS_SAMPLE / IMU_SAMPLE decoders (avo_uart_proto, avo_payloads).
 * Streaming: works on an InputStream, memory use is one block (≤ 64 KB).
 * Stops at the first invalid block exactly like the firmware (a torn block is never interpreted).
 */
data class RawFileHeader(
    val sessionId: String, val segment: Int, val flags: Int, val createdRtcMs: Long, val createdUptimeMs: Long,
    val bootCount: Long, val chestFw: String, val backFw: String, val chestDev: String, val backDev: String,
    val horseId: Long, val horseName: String, val riderId: Long, val riderName: String, val fenceId: Int,
    val startReason: Int, val exitAction: Int, val preS: Int, val postS: Int, val configCrc: Long,
    val gnssRateHz: Int, val constellations: Int, val imuRateHz: Int, val uartBaud: Long,
) {
    companion object {
        const val SIZE = 512
        fun decode(h: ByteArray): RawFileHeader? {
            if (h.size < SIZE) return null
            if (String(h, 0, 7, Charsets.US_ASCII) != "AVORAW1" || h[7].toInt() != 0) return null
            if (Crc.crc32(h, 0, SIZE - 4) != leU32(h, SIZE - 4)) return null
            val r = ByteReader(h, 8, SIZE)
            val ver = r.u16(); val hl = r.u16()
            if (ver < 1 || hl != SIZE) return null
            val x = RawFileHeader(
                r.str(24), r.u16(), r.u16(), r.u64(), r.u32(), r.u32(), r.str(16), r.str(16), r.str(16), r.str(16),
                r.u32(), r.str(24), r.u32(), r.str(24), r.u8(), r.u8(), r.u8(), r.u8(), r.u8(),
                run { r.skip(3); r.u32() }, r.u8(), r.u8(), r.u16(), r.u32(),
            )
            return if (r.ok) x else null
        }
    }
}

object RecType {
    const val UART_FRAME = 0x01; const val CHEST_EVENT = 0x02; const val CHEST_STATUS = 0x03; const val RTCM_STATS = 0x04
    const val MARKER = 0x05; const val LOSS = 0x06; const val SESSION_START = 0x07; const val SESSION_CLOSE = 0x08
    const val RECOVERY = 0x09; const val CONFIG_SNAPSHOT = 0x0A; const val TIME_REF = 0x0B; const val PREBUFFER_INFO = 0x0C
    const val DECODER_STATS = 0x0D; const val RTCM_BYTES = 0x0E; const val PAUSE = 0x0F; const val RESUME = 0x10
}

object UartType { const val GNSS_SAMPLE = 0x10; const val GNSS_UBX = 0x11; const val IMU_SAMPLE = 0x20; const val STATUS = 0x41; const val TIME_SYNC = 0x03 }

/** Decoded GNSS_SAMPLE (compact NAV-PVT) — only fields the analysis uses plus timing. */
data class GnssSample(
    val itowMs: Long, val year: Int, val month: Int, val day: Int, val hour: Int, val min: Int, val sec: Int, val valid: Int,
    val fixType: Int, val flags: Int, val flags3: Int, val numSv: Int, val lonE7: Int, val latE7: Int, val heightMm: Int,
    val hAccMm: Long, val vAccMm: Long, val gSpeedMmS: Int, val headMotE5: Int, val backRxMs: Long, val navRateHz: Int,
    val chestUs: Long,
) {
    val gnssFixOk get() = flags and 1 != 0
    val carrSoln get() = (flags shr 6) and 3
    val invalidLlh get() = flags3 and 1 != 0
    val usable get() = gnssFixOk && !invalidLlh && fixType in 2..4
    companion object {
        const val V1_LEN = 85
        fun decode(p: ByteArray, off: Int, len: Int, chestUs: Long): GnssSample? {
            if (len < V1_LEN) return null
            val r = ByteReader(p, off, off + len)
            val itow = r.u32(); val y = r.u16(); val mo = r.u8(); val d = r.u8(); val h = r.u8(); val mi = r.u8(); val s = r.u8(); val v = r.u8()
            r.i32(); r.u32()
            val ft = r.u8(); val fl = r.u8(); val f3 = r.u16(); val sv = r.u8(); val lon = r.i32(); val lat = r.i32(); val hgt = r.i32(); r.i32()
            val ha = r.u32(); val va = r.u32(); r.i32(); r.i32(); r.i32(); val gs = r.i32(); val hm = r.i32(); r.u32(); r.u32(); r.u16()
            val brx = r.u32(); r.u8(); val nr = r.u8()
            return if (r.ok) GnssSample(itow, y, mo, d, h, mi, s, v, ft, fl, f3, sv, lon, lat, hgt, ha, va, gs, hm, brx, nr, chestUs) else null
        }
    }
}

data class UartFrame(val type: Int, val src: Int, val seq: Int, val tMs: Long, val payloadOff: Int, val payloadLen: Int)

object UartCodec {
    const val HDR = 15
    /** Validates a complete stored frame (sync, header CRC-8, CRC-32). */
    fun parse(b: ByteArray, off: Int, len: Int): UartFrame? {
        if (len < HDR + 4) return null
        if ((b[off].toInt() and 0xFF) != 0xA5 || (b[off + 1].toInt() and 0xFF) != 0x5A) return null
        if (Crc.crc8(b, off + 2, 12) != (b[off + 14].toInt() and 0xFF)) return null
        val plen = leU16(b, off + 8)
        if (HDR + plen + 4 != len) return null
        if (Crc.crc32(b, off + 2, HDR - 2 + plen) != leU32(b, off + HDR + plen)) return null
        return UartFrame(b[off + 3].toInt() and 0xFF, b[off + 5].toInt() and 0xFF, leU16(b, off + 6), leU32(b, off + 10), off + HDR, plen)
    }
}

data class RawScan(
    val header: RawFileHeader?, val blocks: Int, val records: Int, val fileSize: Long, val validEnd: Long,
    val firstBlockSeq: Long, val lastBlockSeq: Long, val cleanClose: Boolean, val tailGarbage: Boolean, val badRecords: Int,
)

interface RawVisitor { fun record(type: Int, flags: Int, chestUs: Long, data: ByteArray, off: Int, len: Int, blockSeq: Long, blockFlags: Int) }

object RawReader {
    const val BLOCK_HDR = 36
    const val BLOCK_MAGIC = 0x424F5641L
    const val MAX_PAYLOAD = 64 * 1024
    const val REC_HDR = 12

    private fun readFully(ins: InputStream, b: ByteArray, n: Int): Int {
        var got = 0
        while (got < n) { val k = ins.read(b, got, n - got); if (k < 0) break; got += k }
        return got
    }

    fun scan(ins: InputStream, visitor: RawVisitor? = null): RawScan {
        val hdr = ByteArray(RawFileHeader.SIZE)
        var pos = readFully(ins, hdr, hdr.size).toLong()
        val header = if (pos == hdr.size.toLong()) RawFileHeader.decode(hdr) else null
        if (header == null) return RawScan(null, 0, 0, pos + drain(ins), 0, 0, 0, false, pos > 0, 0)
        val bh = ByteArray(BLOCK_HDR)
        val payload = ByteArray(MAX_PAYLOAD)
        var blocks = 0; var records = 0; var bad = 0; var clean = false
        var first = 0L; var last = 0L
        var validEnd = pos
        var tail = 0L
        while (true) {
            val g = readFully(ins, bh, BLOCK_HDR)
            if (g == 0) break
            if (g < BLOCK_HDR) { tail = g.toLong(); break }
            val ok = leU32(bh, 0) == BLOCK_MAGIC && Crc.crc32(bh, 0, 32) == leU32(bh, 32)
            val plen = leU32(bh, 8)
            if (!ok || plen > MAX_PAYLOAD) { tail = g + drain(ins); break }
            val pl = plen.toInt()
            val g2 = readFully(ins, payload, pl)
            if (g2 < pl || Crc.crc32(payload, 0, pl) != leU32(bh, 28)) { tail = g.toLong() + g2 + drain(ins); break }
            val seq = leU32(bh, 4); val nrec = leU16(bh, 12); val bflags = leU16(bh, 14)
            if (blocks == 0) first = seq
            last = seq
            var p = 0
            var n = 0
            while (n < nrec && p + REC_HDR <= pl) {
                val type = payload[p].toInt() and 0xFF
                val fl = payload[p + 1].toInt() and 0xFF
                val len = leU16(payload, p + 2)
                val us = leU64(payload, p + 4)
                if (p + REC_HDR + len > pl) { bad++; break }
                visitor?.record(type, fl, us, payload, p + REC_HDR, len, seq, bflags)
                p += REC_HDR + len; n++
            }
            if (n != nrec) bad += nrec - n
            records += n
            blocks++
            if (bflags and 0x0002 != 0) clean = true
            pos += BLOCK_HDR + pl
            validEnd = pos
        }
        return RawScan(header, blocks, records, validEnd + tail, validEnd, first, last, clean, tail > 0, bad)
    }

    private fun drain(ins: InputStream): Long { var t = 0L; val b = ByteArray(8192); while (true) { val k = ins.read(b); if (k < 0) return t; t += k } }
}

/** Training metrics computed only from what the file actually contains. */
data class TrainingAnalysis(
    val scan: RawScan,
    val gnssSamples: Int, val gnssUsable: Int, val noFix: Int,
    val autonomousEpochs: Int, val floatEpochs: Int, val fixEpochs: Int,
    val distanceM: Double, val maxSpeedMs: Double, val avgSpeedMs: Double?,
    val durationS: Double?, val navRateHz: Int,
    val imuBatches: Int, val imuSamples: Long, val markers: Int, val badUartFrames: Int,
    val track: List<TrackPoint>,
) {
    val fixTimeS get() = if (navRateHz > 0) fixEpochs.toDouble() / navRateHz else null
    val floatTimeS get() = if (navRateHz > 0) floatEpochs.toDouble() / navRateHz else null
    val imuAvailable get() = imuSamples > 0
}

data class TrackPoint(val p: GeoPoint, val itowMs: Long, val speedMs: Double, val carrSoln: Int, val hAccM: Double)

class TrainingAnalyzer(private val maxTrackPoints: Int = 5000) : RawVisitor {
    private var gnss = 0; private var usable = 0; private var noFix = 0
    private var auto = 0; private var flt = 0; private var fix = 0
    private var dist = 0.0; private var maxSpeed = 0.0
    private var prev: GeoPoint? = null
    private var firstItow = -1L; private var lastItow = -1L
    private var rate = 0
    private var imuB = 0; private var imuS = 0L; private var markers = 0; private var badUart = 0
    private val track = ArrayList<TrackPoint>()
    private var trackStride = 1; private var trackCounter = 0

    override fun record(type: Int, flags: Int, chestUs: Long, data: ByteArray, off: Int, len: Int, blockSeq: Long, blockFlags: Int) {
        when (type) {
            RecType.MARKER -> markers++
            RecType.UART_FRAME -> {
                val f = UartCodec.parse(data, off, len) ?: run { badUart++; return }
                when (f.type) {
                    UartType.GNSS_SAMPLE -> GnssSample.decode(data, f.payloadOff, f.payloadLen, chestUs)?.let { onGnss(it) } ?: badUart++
                    UartType.IMU_SAMPLE -> if (f.payloadLen >= 24) { imuB++; imuS += data[f.payloadOff + 2].toInt() and 0xFF }
                }
            }
        }
    }

    private fun onGnss(s: GnssSample) {
        gnss++
        if (s.navRateHz > 0) rate = s.navRateHz
        if (!s.usable) { noFix++; return }
        usable++
        when (s.carrSoln) { 0 -> auto++; 1 -> flt++; else -> fix++ }
        val p = GeoPoint(s.latE7, s.lonE7)
        prev?.let { dist += haversineM(it, p) }
        prev = p
        val v = s.gSpeedMmS / 1000.0
        if (v > maxSpeed) maxSpeed = v
        if (firstItow < 0) firstItow = s.itowMs
        lastItow = s.itowMs
        if (trackCounter++ % trackStride == 0) {
            track += TrackPoint(p, s.itowMs, v, s.carrSoln, s.hAccMm / 1000.0)
            if (track.size >= maxTrackPoints) { // decimate by 2, keep memory bounded
                val keep = track.filterIndexed { i, _ -> i % 2 == 0 }
                track.clear(); track.addAll(keep); trackStride *= 2
            }
        }
    }

    fun result(scan: RawScan): TrainingAnalysis {
        // itow wraps weekly; a session never lasts a week, so handle one wrap.
        val dur = if (firstItow >= 0) { var d = lastItow - firstItow; if (d < 0) d += 604_800_000L; d / 1000.0 } else null
        return TrainingAnalysis(scan, gnss, usable, noFix, auto, flt, fix, dist, maxSpeed,
            if (dur != null && dur > 0) dist / dur else null, dur, rate, imuB, imuS, markers, badUart, track.toList())
    }

    companion object {
        /** Analyses one or more segments of the same session, in order. */
        fun analyze(segments: List<() -> InputStream>): TrainingAnalysis {
            val a = TrainingAnalyzer()
            var last: RawScan? = null
            for (open in segments) open().use { last = RawReader.scan(it, a) }
            return a.result(last ?: RawScan(null, 0, 0, 0, 0, 0, 0, false, false, 0))
        }
    }
}
