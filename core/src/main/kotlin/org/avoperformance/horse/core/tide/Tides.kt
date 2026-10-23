package org.avoperformance.horse.core.tide

import kotlin.math.*

/** Official IHM extreme: UTC epoch ms, height in metres above the port chart datum. */
data class TideExtreme(val tMs: Long, val heightM: Double, val high: Boolean, val coefficient: Int? = null)

data class TideLevel(val heightM: Double, val rising: Boolean)

data class SunTimes(val riseMs: Long?, val setMs: Long?, val dawnMs: Long?, val duskMs: Long?, val noonMs: Long)

data class MoonInfo(val phase: MoonPhase, val illumination: Int, val ageDays: Double)

enum class MoonPhase(val label: String) {
    NEW("Luna nueva"), WAXING_CRESCENT("Creciente"), FIRST_QUARTER("Cuarto creciente"),
    WAXING_GIBBOUS("Gibosa creciente"), FULL("Luna llena"), WANING_GIBBOUS("Gibosa menguante"),
    LAST_QUARTER("Cuarto menguante"), WANING_CRESCENT("Menguante")
}

object TideMath {
    /** Cosine interpolation between consecutive official extremes (the method used by tide tables). */
    fun levelAt(ext: List<TideExtreme>, tMs: Long): TideLevel? {
        val i = ext.indexOfFirst { it.tMs > tMs }
        if (i <= 0) return null
        val a = ext[i - 1]; val b = ext[i]
        val f = (tMs - a.tMs).toDouble() / (b.tMs - a.tMs)
        return TideLevel(a.heightM + (b.heightM - a.heightM) * (1 - cos(PI * f)) / 2, b.heightM > a.heightM)
    }

    fun curve(ext: List<TideExtreme>, fromMs: Long, toMs: Long, stepMs: Long = 10 * 60_000L): List<Pair<Long, Double>> {
        val out = ArrayList<Pair<Long, Double>>()
        var t = fromMs
        while (t <= toMs) { levelAt(ext, t)?.let { out += t to it.heightM }; t += stepMs }
        return out
    }

    /** Mean range between consecutive high/low pairs (reference for coefficient 70). */
    fun meanRange(ext: List<TideExtreme>): Double? {
        var sum = 0.0; var n = 0
        for (i in 1 until ext.size) if (ext[i].high != ext[i - 1].high) { sum += abs(ext[i].heightM - ext[i - 1].heightM); n++ }
        return if (n == 0) null else sum / n
    }

    /** Coefficient for each high water: 70 × range / mean range, clamped to the usual 20..120 scale. */
    fun withCoefficients(ext: List<TideExtreme>, meanRange: Double?): List<TideExtreme> {
        if (meanRange == null || meanRange <= 0) return ext
        return ext.mapIndexed { i, e ->
            if (!e.high) return@mapIndexed e
            val ranges = listOfNotNull(ext.getOrNull(i - 1), ext.getOrNull(i + 1)).filter { !it.high }.map { e.heightM - it.heightM }
            if (ranges.isEmpty()) e else e.copy(coefficient = (70 * ranges.average() / meanRange).roundToInt().coerceIn(20, 120))
        }
    }

    fun coefficientAt(ext: List<TideExtreme>, tMs: Long): Int? =
        ext.filter { it.coefficient != null }.minByOrNull { abs(it.tMs - tMs) }?.coefficient

    fun coefficientLabel(c: Int?): String = when {
        c == null -> ""
        c >= 95 -> "Vivas fuertes"
        c >= 70 -> "Mareas vivas"
        c >= 45 -> "Marea media"
        else -> "Mareas muertas"
    }

    /** 0 = low water, 1 = high water, relative to the surrounding extremes. */
    fun fraction(ext: List<TideExtreme>, tMs: Long): Double? {
        val i = ext.indexOfFirst { it.tMs > tMs }
        if (i <= 0) return null
        val a = ext[i - 1]; val b = ext[i]
        val lv = levelAt(ext, tMs) ?: return null
        val lo = min(a.heightM, b.heightM); val hi = max(a.heightM, b.heightM)
        return if (hi - lo < 1e-6) 0.5 else (lv.heightM - lo) / (hi - lo)
    }
}

object Astro {
    private const val RAD = PI / 180

    /** Sunrise/sunset (≈1 min) and civil twilight for the UTC day containing [ms]. */
    fun sun(ms: Long, lat: Double, lon: Double): SunTimes {
        val jd = floor(ms / 86_400_000.0) + 2440588
        val n = jd - 2451545 + 0.0008
        val jStar = n - lon / 360
        val m = (357.5291 + 0.98560028 * jStar) % 360
        val c = 1.9148 * sin(m * RAD) + 0.02 * sin(2 * m * RAD) + 0.0003 * sin(3 * m * RAD)
        val lambda = (m + c + 180 + 102.9372) % 360
        val transit = 2451545 + jStar + 0.0053 * sin(m * RAD) - 0.0069 * sin(2 * lambda * RAD)
        val sinD = sin(lambda * RAD) * sin(23.4397 * RAD)
        val cosD = cos(asin(sinD))
        fun toMs(j: Double) = ((j - 2440587.5) * 86_400_000).roundToLong()
        fun hourAngle(angle: Double): Double? {
            val cw = (sin(angle * RAD) - sin(lat * RAD) * sinD) / (cos(lat * RAD) * cosD)
            return if (cw < -1 || cw > 1) null else acos(cw) / RAD
        }
        val w = hourAngle(-0.833); val wc = hourAngle(-6.0)
        return SunTimes(w?.let { toMs(transit - it / 360) }, w?.let { toMs(transit + it / 360) },
            wc?.let { toMs(transit - it / 360) }, wc?.let { toMs(transit + it / 360) }, toMs(transit))
    }

    fun moon(ms: Long): MoonInfo {
        val month = 29.53058770576
        val days = (ms - 947_182_440_000L) / 86_400_000.0
        var cycle = (days % month) / month
        if (cycle < 0) cycle += 1
        val phase = when {
            cycle < 0.03 || cycle >= 0.97 -> MoonPhase.NEW
            cycle < 0.22 -> MoonPhase.WAXING_CRESCENT
            cycle < 0.28 -> MoonPhase.FIRST_QUARTER
            cycle < 0.47 -> MoonPhase.WAXING_GIBBOUS
            cycle < 0.53 -> MoonPhase.FULL
            cycle < 0.72 -> MoonPhase.WANING_GIBBOUS
            cycle < 0.78 -> MoonPhase.LAST_QUARTER
            else -> MoonPhase.WANING_CRESCENT
        }
        return MoonInfo(phase, ((1 - cos(cycle * 2 * PI)) / 2 * 100).roundToInt(), cycle * month)
    }

    /** Moon altitude (degrees) with a low-precision ephemeris (~0.3°), enough for rise/set to a few minutes. */
    fun moonAltitude(ms: Long, lat: Double, lon: Double): Double {
        val d = (ms - 946_728_000_000L) / 86_400_000.0 // days since J2000.0
        val l = (218.316 + 13.176396 * d) * RAD
        val mm = (134.963 + 13.064993 * d) * RAD
        val f = (93.272 + 13.229350 * d) * RAD
        val lng = l + 6.289 * RAD * sin(mm)
        val lat2 = 5.128 * RAD * sin(f)
        val e = 23.4397 * RAD
        val ra = atan2(sin(lng) * cos(e) - tan(lat2) * sin(e), cos(lng))
        val dec = asin(sin(lat2) * cos(e) + cos(lat2) * sin(e) * sin(lng))
        val sidereal = (280.16 + 360.9856235 * d) * RAD + lon * RAD
        val h = sidereal - ra
        val phi = lat * RAD
        return asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h)) / RAD
    }

    /** Moonrise and moonset within [fromMs, fromMs + 24 h); either may be null on some days. */
    fun moonRiseSet(fromMs: Long, lat: Double, lon: Double): Pair<Long?, Long?> {
        val step = 10 * 60_000L
        val h0 = 0.133 // parallax minus refraction and semi-diameter
        var rise: Long? = null; var set: Long? = null
        var prev = moonAltitude(fromMs, lat, lon) - h0
        var t = fromMs
        while (t < fromMs + 86_400_000L) {
            val nt = t + step
            val cur = moonAltitude(nt, lat, lon) - h0
            if (prev < 0 && cur >= 0 && rise == null) rise = t + (step * (-prev / (cur - prev))).toLong()
            if (prev >= 0 && cur < 0 && set == null) set = t + (step * (prev / (prev - cur))).toLong()
            prev = cur; t = nt
        }
        return rise to set
    }
}
