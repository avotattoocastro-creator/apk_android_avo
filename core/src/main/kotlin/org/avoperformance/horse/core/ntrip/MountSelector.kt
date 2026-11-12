package org.avoperformance.horse.core.ntrip

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * One STR line of an NTRIP sourcetable (NTRIP 2.0, fields separated by ';'):
 *
 *   STR;mountpoint;identifier;format;format-details;carrier;nav-system;network;country;latitude;longitude;
 *   nmea;solution;generator;compr-encryp;authentication;fee;bitrate;misc
 *
 * [carrier]: 0 none, 1 L1, 2 L1+L2 (dual frequency). [nmea]: the caster needs GGA from the client.
 * [network]: solution 1 = network/VRS (corrections built for the client position, any distance inside the
 * network); 0 = single base (accuracy degrades with distance to that base).
 */
data class SourceEntry(
    val mountpoint: String,
    val identifier: String,
    val format: String,
    val formatDetails: String,
    val carrier: Int,
    val navSystems: String,
    val networkName: String,
    val country: String,
    val lat: Double?,
    val lon: Double?,
    val nmea: Boolean,
    val network: Boolean,
) {
    /** RTCM 3.x is the only format the ZED-F9P uses. */
    val isRtcm3: Boolean get() = format.replace(" ", "").uppercase().startsWith("RTCM3")
    val hasPosition: Boolean get() = lat != null && lon != null && !(lat == 0.0 && lon == 0.0) && lat in -90.0..90.0 && lon in -180.0..180.0
    val dualFrequency: Boolean get() = carrier >= 2
    /** Declared L1 only: the ZED-F9P reaches RTK FIX much worse with it. Carrier 0 (not declared) is not penalised. */
    val singleFrequency: Boolean get() = carrier == 1

    companion object {
        fun parseAll(text: String): List<SourceEntry> = text.lineSequence().mapNotNull { parse(it) }.toList()

        fun parse(line: String): SourceEntry? {
            if (!line.startsWith("STR;")) return null
            val f = line.trimEnd('\r').split(';')
            val mount = f.getOrNull(1)?.trim().orEmpty()
            if (mount.isEmpty() || mount.any { it.isWhitespace() || it == '/' }) return null
            fun s(i: Int) = f.getOrNull(i)?.trim().orEmpty()
            fun d(i: Int) = s(i).replace(',', '.').toDoubleOrNull()
            return SourceEntry(mount, s(2), s(3), s(4), s(5).toIntOrNull() ?: 0, s(6), s(7), s(8), d(9), d(10),
                s(11) == "1", s(12) == "1")
        }
    }
}

/** Selection of the mountpoint for a position. */
data class MountChoice(
    /** Main mountpoint and backups, in order. */
    val ordered: List<String>,
    val main: SourceEntry,
    /** Distance from the position to the main base (km); null for a network without a meaningful position. */
    val distanceKm: Double?,
    val reason: String,
)

data class RankedMount(val entry: SourceEntry, val distanceKm: Double?)

/**
 * Picks the best mountpoint of a caster for the receiver position.
 *
 * - Only RTCM 3.x; dual-frequency bases first (RTK FIX needs L1+L2 corrections).
 * - The nearest single base within [maxBaseKm] wins (short baseline = faster, more reliable FIX).
 * - Beyond that distance a network/VRS mountpoint (if the caster has one) is better than a far base.
 * - If there is nothing better, the nearest base anyway.
 * - Hysteresis: the current mountpoint is kept unless the new one is at least [switchMarginKm] closer and 20 %
 *   closer, so the source does not bounce between two similar bases.
 */
object MountSelector {
    const val DEFAULT_MAX_BASE_KM = 20
    const val SWITCH_MARGIN_KM = 5.0
    const val BACKUPS = 3

    fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0088
        val p1 = Math.toRadians(lat1); val p2 = Math.toRadians(lat2)
        val dp = p2 - p1; val dl = Math.toRadians(lon2 - lon1)
        val a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(sqrt(a.coerceIn(0.0, 1.0)))
    }

    /** Usable mountpoints ranked for the position: single bases by distance (dual frequency first), networks apart. */
    fun rank(entries: List<SourceEntry>, lat: Double, lon: Double): List<RankedMount> =
        entries.filter { it.isRtcm3 }.distinctBy { it.mountpoint }
            .map { RankedMount(it, if (it.hasPosition) distanceKm(lat, lon, it.lat!!, it.lon!!) else null) }
            .sortedWith(compareBy<RankedMount>({ it.entry.network }, { it.entry.singleFrequency }, { it.distanceKm ?: Double.MAX_VALUE }))

    fun choose(
        entries: List<SourceEntry>, lat: Double, lon: Double,
        current: String? = null, maxBaseKm: Int = DEFAULT_MAX_BASE_KM, switchMarginKm: Double = SWITCH_MARGIN_KM,
    ): MountChoice? {
        val ranked = rank(entries, lat, lon)
        if (ranked.isEmpty()) return null
        val bases = ranked.filter { !it.entry.network && it.distanceKm != null }
            .sortedWith(compareBy<RankedMount>({ it.entry.singleFrequency || it.distanceKm!! > maxBaseKm }, { it.distanceKm }))
        val networks = ranked.filter { it.entry.network }
            .sortedWith(compareBy<RankedMount>({ it.entry.singleFrequency }, { it.distanceKm ?: Double.MAX_VALUE }))
        val nearBase = bases.firstOrNull()?.takeIf { it.distanceKm!! <= maxBaseKm && !it.entry.singleFrequency }
        val (best, reason) = when {
            nearBase != null -> nearBase to "base a ${fmt(nearBase.distanceKm!!)} km"
            networks.isNotEmpty() -> networks.first() to "red / VRS (ninguna base a menos de $maxBaseKm km)"
            bases.isNotEmpty() -> bases.minWith(compareBy({ it.entry.singleFrequency }, { it.distanceKm!! })).let { it to "base más cercana, a ${fmt(it.distanceKm!!)} km (lejos o solo L1: el FIX será más lento)" }
            else -> ranked.first() to "único mountpoint RTCM 3 sin posición"
        }
        // hysteresis: keep the current one if it is still a reasonable choice
        val cur = ranked.firstOrNull { it.entry.mountpoint == current }
        val main = if (cur != null && cur.entry.mountpoint != best.entry.mountpoint && keep(cur, best, maxBaseKm, switchMarginKm)) cur else best
        val why = if (main === cur && cur.entry.mountpoint != best.entry.mountpoint) "se mantiene ${cur.entry.mountpoint} (${best.entry.mountpoint} no es claramente mejor)" else reason
        val order = (listOf(main) + (if (main.entry.network) bases else bases.filter { it !== main }).take(BACKUPS) + networks.filter { it !== main }.take(1))
            .map { it.entry.mountpoint }.distinct()
        return MountChoice(order, main.entry, main.distanceKm, why)
    }

    private fun keep(cur: RankedMount, best: RankedMount, maxBaseKm: Int, margin: Double): Boolean {
        if (!cur.entry.isRtcm3) return false
        val cd = cur.distanceKm; val bd = best.distanceKm
        return when {
            // both single bases: switch only if clearly closer
            !cur.entry.network && !best.entry.network && cd != null && bd != null ->
                cd <= maxBaseKm * 1.5 && !(cd - bd >= margin && bd <= cd * 0.8)
            // on a network, a base inside the limit is better (shorter baseline) → switch
            cur.entry.network && !best.entry.network -> false
            // on a far base, a network is better → switch; on a near one, keep it
            !cur.entry.network && best.entry.network -> cd != null && cd <= maxBaseKm
            else -> true
        }
    }

    private fun fmt(km: Double) = String.format(java.util.Locale.US, "%.1f", km).replace('.', ',')
}
