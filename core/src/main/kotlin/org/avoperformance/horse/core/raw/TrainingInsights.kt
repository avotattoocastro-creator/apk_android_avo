package org.avoperformance.horse.core.raw

import kotlin.math.abs
import kotlin.math.sqrt

/** One cadence estimate: chest time (µs), beats per minute and autocorrelation strength (0..1). */
data class CadencePoint(val chestUs: Long, val spm: Double, val strength: Double)

/**
 * Cadence from the girth IMU without knowing the sensor scale: the dominant period of the
 * acceleration magnitude, found by normalised autocorrelation over 6 s windows every 2 s.
 * Range 36–240 beats/min. Windows without movement are skipped (no value is invented).
 */
class CadenceEstimator(
    private val windowUs: Long = 6_000_000,
    private val hopUs: Long = 2_000_000,
    private val rateHz: Int = 50,
) {
    private val t = ArrayList<Long>()
    private val v = ArrayList<Double>()
    private var lastEmitUs = Long.MIN_VALUE
    private val out = ArrayList<CadencePoint>()

    fun reset() { t.clear(); v.clear(); lastEmitUs = Long.MIN_VALUE }

    fun add(chestUs: Long, magnitude: Double) {
        if (!magnitude.isFinite()) return
        if (t.isNotEmpty() && chestUs < t.last()) { if (t.last() - chestUs > 1_000_000) reset() else return }
        t += chestUs; v += magnitude
        val cut = chestUs - windowUs
        var drop = 0
        while (drop < t.size && t[drop] < cut) drop++
        if (drop > 0) { t.subList(0, drop).clear(); v.subList(0, drop).clear() }
        if (lastEmitUs == Long.MIN_VALUE) lastEmitUs = chestUs
        if (chestUs - lastEmitUs >= hopUs && t.last() - t.first() >= windowUs * 5 / 6) {
            lastEmitUs = chestUs
            estimate()?.let { out += it }
        }
    }

    fun result(): List<CadencePoint> = out.toList()

    private fun estimate(): CadencePoint? {
        val start = t.first(); val end = t.last()
        val stepUs = 1_000_000L / rateHz
        val n = ((end - start) / stepUs).toInt()
        if (n < rateHz * 3) return null
        val x = DoubleArray(n)
        var j = 0
        for (i in 0 until n) {
            val ti = start + i * stepUs
            while (j < t.size - 2 && t[j + 1] < ti) j++
            val t0 = t[j]; val t1 = t[j + 1]
            x[i] = if (t1 == t0) v[j] else v[j] + (v[j + 1] - v[j]) * (ti - t0).toDouble() / (t1 - t0)
        }
        val mean = x.average()
        for (i in x.indices) x[i] -= mean
        val energy = x.sumOf { it * it }
        val std = sqrt(energy / n)
        if (mean <= 0 || std / mean < 0.03) return null           // standing still
        val minLag = (rateHz * 0.25).toInt()                      // 240 /min
        val maxLag = (rateHz * 1.67).toInt().coerceAtMost(n / 2)  // 36 /min
        val r = DoubleArray(maxLag + 2)
        for (lag in minLag - 1..maxLag + 1) {
            var s = 0.0
            for (i in 0 until n - lag) s += x[i] * x[i + lag]
            r[lag] = s / energy * n / (n - lag)
        }
        // Local maxima; take the earliest one close to the best (avoids reporting a multiple of the period).
        val peaks = (minLag..maxLag).filter { r[it] > r[it - 1] && r[it] >= r[it + 1] && r[it] > 0.3 }
        if (peaks.isEmpty()) return null
        val best = peaks.maxOf { r[it] }
        val lag = peaks.first { r[it] >= 0.85 * best }
        // Parabolic refinement of the peak position.
        val a = r[lag - 1]; val b = r[lag]; val c = r[lag + 1]
        val den = a - 2 * b + c
        val shift = if (abs(den) < 1e-12) 0.0 else (0.5 * (a - c) / den).coerceIn(-0.5, 0.5)
        val periodS = (lag + shift) / rateHz
        return CadencePoint((start + end) / 2, 60.0 / periodS, b.coerceIn(0.0, 1.0))
    }
}

enum class Gait(val texto: String) { STOPPED("Parado"), WALK("Paso"), TROT("Trote"), GALLOP("Galope") }

enum class EventKind(val texto: String) { START("Salida"), MAX_SPEED("Velocidad máxima"), FIRST_GALLOP("Galope"), MARKER("Marca"), FINISH("Llegada") }

data class TrainingEvent(val kind: EventKind, val index: Int, val timeS: Double, val value: Double? = null)

/** Contiguous fast effort on the track (indices inclusive). */
data class Effort(val startIdx: Int, val endIdx: Int, val distanceM: Double, val durationS: Double, val avgSpeedMs: Double, val maxSpeedMs: Double)

data class Split(val number: Int, val fromM: Double, val toM: Double, val durationS: Double) {
    val avgSpeedMs get() = if (durationS > 0) (toM - fromM) / durationS else 0.0
}

data class Insights(
    /** Seconds since the first GNSS point (handles one week rollover). */
    val timeS: DoubleArray,
    /** Cumulative distance (m) along the track. */
    val distM: DoubleArray,
    /** Longitudinal acceleration from GNSS speed (m/s²), 0 where the time step is invalid. */
    val accelMs2: DoubleArray,
    /** Smoothed altitude (m, NaN when unknown). */
    val altM: DoubleArray,
    /** Cadence (beats/min) mapped to track points, NaN where not measured. */
    val cadence: DoubleArray,
    val maxAccelG: Double?, val maxDecelG: Double?,
    val altMaxM: Double?, val altMinM: Double?, val gainM: Double?, val lossM: Double?,
    val slopeMaxPct: Double?, val slopeMinPct: Double?, val slopeMeanAbsPct: Double?,
    val gaitSeconds: Map<Gait, Double>,
    val efforts: List<Effort>,
    val splits: List<Split>, val splitUnitM: Double,
    val events: List<TrainingEvent>,
    val cadenceMax: Double?, val cadenceMean: Double?,
    val avgSatellites: Double?, val avgHAccM: Double?, val avgVAccM: Double?,
) {
    val movingSeconds get() = gaitSeconds.filterKeys { it != Gait.STOPPED }.values.sum()
    fun gaitShare(g: Gait): Double { val total = gaitSeconds.values.sum(); return if (total > 0) (gaitSeconds[g] ?: 0.0) / total else 0.0 }
}

/** Derived metrics computed ONLY from samples present in the file. */
object TrainingInsights {
    const val G = 9.80665
    /** Gait limits by GNSS speed (km/h); an estimate, the IMU is not used for gait classification. */
    const val STOP_KMH = 1.5
    const val WALK_MAX_KMH = 8.0
    const val TROT_MAX_KMH = 16.0

    fun gaitOf(speedMs: Double): Gait {
        val k = speedMs * 3.6
        return when { k < STOP_KMH -> Gait.STOPPED; k < WALK_MAX_KMH -> Gait.WALK; k < TROT_MAX_KMH -> Gait.TROT; else -> Gait.GALLOP }
    }

    fun compute(a: TrainingAnalysis): Insights {
        val tr = a.track
        val n = tr.size
        val time = DoubleArray(n)
        val dist = DoubleArray(n)
        val acc = DoubleArray(n)
        for (i in 1 until n) {
            var d = tr[i].itowMs - tr[0].itowMs
            if (d < 0) d += 604_800_000L
            time[i] = d / 1000.0
            dist[i] = dist[i - 1] + org.avoperformance.horse.core.geo.haversineM(tr[i - 1].p, tr[i].p)
            val dt = time[i] - time[i - 1]
            val dv = tr[i].speedMs - tr[i - 1].speedMs
            acc[i] = if (dt in 0.08..10.0 && tr[i].speedMs.isFinite() && tr[i - 1].speedMs.isFinite())
                (dv / dt).takeIf { it.isFinite() && abs(it) <= 12.0 } ?: 0.0 else 0.0
        }
        val accValid = (1 until n).map { acc[it] }
        val maxAcc = accValid.maxOrNull()?.takeIf { it > 0 }?.div(G)
        val maxDec = accValid.minOrNull()?.takeIf { it < 0 }?.let { -it / G }

        // Altitude: 5-point moving average of valid hMSL values.
        val rawAlt = DoubleArray(n) { tr[it].altM }
        val alt = DoubleArray(n) { i ->
            var s = 0.0; var k = 0
            for (j in maxOf(0, i - 2)..minOf(n - 1, i + 2)) if (rawAlt[j].isFinite() && rawAlt[j] != 0.0) { s += rawAlt[j]; k++ }
            if (k > 0) s / k else Double.NaN
        }
        val altValid = alt.filter { it.isFinite() }
        val hasAlt = altValid.size >= 10
        var gain = 0.0; var loss = 0.0
        if (hasAlt) {
            var ref = Double.NaN
            for (h in alt) {
                if (!h.isFinite()) continue
                if (!ref.isFinite()) { ref = h; continue }
                if (h - ref >= 1.0) { gain += h - ref; ref = h } else if (ref - h >= 1.0) { loss += ref - h; ref = h }
            }
        }
        val slopes = ArrayList<Double>()
        if (hasAlt && n > 2 && dist[n - 1] > 50) {
            var j = 0
            for (i in 0 until n) {
                if (!alt[i].isFinite()) continue
                if (j < i) j = i
                while (j < n - 1 && dist[j] - dist[i] < 25.0) j++
                val dd = dist[j] - dist[i]
                if (dd >= 25.0 && alt[j].isFinite()) slopes += ((alt[j] - alt[i]) / dd * 100).coerceIn(-60.0, 60.0)
            }
        }

        // Gait time (dt capped at 2 s so gaps are not counted as riding).
        val gait = Gait.values().associateWith { 0.0 }.toMutableMap()
        for (i in 1 until n) {
            val dt = (time[i] - time[i - 1]).coerceIn(0.0, 2.0)
            val g = gaitOf(tr[i].speedMs)
            gait[g] = gait.getValue(g) + dt
        }

        val efforts = efforts(a, time, dist)
        val total = if (n > 0) dist[n - 1] else 0.0
        val unit = when { total >= 2000 -> 1000.0; total >= 1000 -> 500.0; else -> 250.0 }
        val splits = splits(time, dist, unit)

        // Cadence on the track.
        val cad = DoubleArray(n) { Double.NaN }
        val goodCadence = a.cadence.filter { it.strength >= 0.4 && it.spm in 36.0..240.0 }
        if (goodCadence.isNotEmpty() && n > 0 && tr.any { it.chestUs != 0L }) {
            for (i in 0 until n) {
                val us = tr[i].chestUs
                if (us == 0L) continue
                val k = nearest(goodCadence, us)
                val c = goodCadence[k]
                if (abs(c.chestUs - us) <= 4_000_000) cad[i] = c.spm
            }
        }

        val events = ArrayList<TrainingEvent>()
        if (n > 0) {
            events += TrainingEvent(EventKind.START, 0, 0.0)
            val iMax = (0 until n).maxByOrNull { tr[it].speedMs } ?: 0
            if (tr[iMax].speedMs > 0) events += TrainingEvent(EventKind.MAX_SPEED, iMax, time[iMax], tr[iMax].speedMs)
            firstGallop(a, time)?.let { events += TrainingEvent(EventKind.FIRST_GALLOP, it, time[it], tr[it].speedMs) }
            if (tr.any { it.chestUs != 0L }) a.markerUs.forEach { us ->
                val k = (0 until n).minByOrNull { abs(tr[it].chestUs - us) } ?: return@forEach
                if (abs(tr[k].chestUs - us) <= 10_000_000) events += TrainingEvent(EventKind.MARKER, k, time[k])
            }
            events += TrainingEvent(EventKind.FINISH, n - 1, time[n - 1])
        }

        return Insights(
            time, dist, acc, alt, cad, maxAcc, maxDec,
            if (hasAlt) altValid.maxOrNull() else null, if (hasAlt) altValid.minOrNull() else null,
            if (hasAlt) gain else null, if (hasAlt) loss else null,
            slopes.maxOrNull(), slopes.minOrNull(), slopes.takeIf { it.isNotEmpty() }?.map { abs(it) }?.average(),
            gait, efforts, splits, unit, events.sortedBy { it.timeS },
            goodCadence.maxOfOrNull { it.spm }, goodCadence.takeIf { it.isNotEmpty() }?.map { it.spm }?.average(),
            tr.filter { it.numSv > 0 }.takeIf { it.isNotEmpty() }?.map { it.numSv }?.average(),
            tr.map { it.hAccM }.filter { it.isFinite() && it > 0 }.takeIf { it.isNotEmpty() }?.average(),
            tr.map { it.vAccM }.filter { it.isFinite() && it > 0 }.takeIf { it.isNotEmpty() }?.average(),
        )
    }

    private fun nearest(list: List<CadencePoint>, us: Long): Int {
        var lo = 0; var hi = list.lastIndex
        while (lo < hi) { val mid = (lo + hi) / 2; if (list[mid].chestUs < us) lo = mid + 1 else hi = mid }
        return if (lo > 0 && abs(list[lo - 1].chestUs - us) < abs(list[lo].chestUs - us)) lo - 1 else lo
    }

    private fun firstGallop(a: TrainingAnalysis, time: DoubleArray): Int? {
        val tr = a.track
        var start = -1
        for (i in tr.indices) {
            if (gaitOf(tr[i].speedMs) == Gait.GALLOP) {
                if (start < 0) start = i
                if (time[i] - time[start] >= 5.0) return start
            } else start = -1
        }
        return null
    }

    /** Fast efforts: runs above 60 % of top speed (at least 8 km/h), gaps ≤ 3 s merged, ≥ 8 s long; fastest first. */
    fun efforts(a: TrainingAnalysis, time: DoubleArray, dist: DoubleArray, max: Int = 5): List<Effort> {
        val tr = a.track
        if (tr.size < 3) return emptyList()
        val top = tr.maxOf { it.speedMs }
        val thr = maxOf(top * 0.6, 8 / 3.6)
        val runs = ArrayList<IntArray>()
        var s = -1; var lastFast = -1
        for (i in tr.indices) {
            if (tr[i].speedMs >= thr) {
                if (s < 0) s = i
                else if (time[i] - time[lastFast] > 3.0) { runs += intArrayOf(s, lastFast); s = i }
                lastFast = i
            }
        }
        if (s >= 0) runs += intArrayOf(s, lastFast)
        return runs.filter { time[it[1]] - time[it[0]] >= 8.0 }.map { r ->
            val d = dist[r[1]] - dist[r[0]]
            val t = time[r[1]] - time[r[0]]
            Effort(r[0], r[1], d, t, if (t > 0) d / t else 0.0, (r[0]..r[1]).maxOf { tr[it].speedMs })
        }.sortedByDescending { it.avgSpeedMs }.take(max)
    }

    /** Splits every [unit] metres, time interpolated at each boundary; last partial split kept if ≥ 30 %. */
    fun splits(time: DoubleArray, dist: DoubleArray, unit: Double): List<Split> {
        val n = dist.size
        if (n < 2 || dist[n - 1] <= 0) return emptyList()
        fun timeAt(m: Double): Double {
            var i = 1
            while (i < n - 1 && dist[i] < m) i++
            val d0 = dist[i - 1]; val d1 = dist[i]
            return if (d1 == d0) time[i] else time[i - 1] + (time[i] - time[i - 1]) * (m - d0) / (d1 - d0)
        }
        val out = ArrayList<Split>()
        var from = 0.0; var k = 1
        while (from + unit <= dist[n - 1]) {
            out += Split(k++, from, from + unit, timeAt(from + unit) - timeAt(from))
            from += unit
        }
        val rest = dist[n - 1] - from
        if (rest >= unit * 0.3) out += Split(k, from, dist[n - 1], time[n - 1] - timeAt(from))
        return out
    }
}
