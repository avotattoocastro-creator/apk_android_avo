package org.avoperformance.horse.core.geo

import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.bytes.ByteWriter
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

enum class FenceType(val code: Int) { NONE(0), CIRCLE(1), POLYGON(2); companion object { fun of(v: Int) = values().firstOrNull { it.code == v } ?: NONE } }

data class GeoPoint(val latE7: Int, val lonE7: Int) {
    val lat get() = latE7 * 1e-7
    val lon get() = lonE7 * 1e-7
    companion object { fun of(lat: Double, lon: Double) = GeoPoint(Math.round(lat * 1e7).toInt(), Math.round(lon * 1e7).toInt()) }
}

/** Geofence exactly as the watch stores it (avo_geo.h FenceDef). */
data class Fence(
    val id: Int,
    val type: FenceType,
    val name: String,
    val center: GeoPoint = GeoPoint(0, 0),
    val radiusCm: Long = 0,
    val vertices: List<GeoPoint> = emptyList(),
) {
    fun encodeBody(w: ByteWriter) {
        w.u8(id).u8(type.code).str(name, 16).i32(center.latE7).i32(center.lonE7).u32(radiusCm).u8(vertices.size)
        for (v in vertices.take(MAX_VERTICES)) { w.i32(v.latE7); w.i32(v.lonE7) }
    }
    fun encodeBody(): ByteArray = ByteWriter().also { encodeBody(it) }.toByteArray()

    /** SET_FENCE request payload: u8 slot + body. */
    fun setFenceRequest(slot: Int): ByteArray = ByteWriter().u8(slot).also { copy(id = slot).encodeBody(it) }.toByteArray()

    /** Same checks and limits as validate_fence() in the firmware. null = valid. */
    fun validate(): String? {
        fun ok(p: GeoPoint) = p.latE7 in -900000000..900000000 && p.lonE7 in -1800000000..1800000000 && !(p.latE7 == 0 && p.lonE7 == 0)
        when (type) {
            FenceType.CIRCLE -> {
                if (!ok(center)) return "Centro no válido"
                if (radiusCm !in 500..500000) return "El radio debe estar entre 5 m y 5 km"
                return null
            }
            FenceType.POLYGON -> {
                if (vertices.size < 3) return "Un polígono necesita al menos 3 vértices"
                if (vertices.size > MAX_VERTICES) return "Máximo $MAX_VERTICES vértices"
                if (!vertices.all { ok(it) }) return "Hay vértices con coordenadas no válidas"
                val fr = LocalFrame(vertices[0])
                val xy = vertices.map { fr.toXY(it) }
                if (xy.any { abs(it.first) > 10000 || abs(it.second) > 10000 }) return "La geocerca es demasiado grande (máx. 10 km)"
                val n = xy.size
                for (i in 0 until n) {
                    val i2 = (i + 1) % n
                    for (j in i + 1 until n) {
                        val j2 = (j + 1) % n
                        if (j == i2 || j2 == i) continue
                        if (segmentsIntersect(xy[i], xy[i2], xy[j], xy[j2])) return "El polígono se corta a sí mismo"
                    }
                }
                var a2 = 0.0
                for (i in 0 until n) { val j = (i + 1) % n; a2 += xy[i].first * xy[j].second - xy[j].first * xy[i].second }
                if (abs(a2) / 2 < 25.0) return "El área es demasiado pequeña (mín. 25 m²)"
                return null
            }
            FenceType.NONE -> return "Sin tipo"
        }
    }

    /** Signed distance to the boundary in metres (negative inside), as the watch computes it. */
    fun signedDistanceM(p: GeoPoint): Double {
        return when (type) {
            FenceType.CIRCLE -> { val fr = LocalFrame(center); val (x, y) = fr.toXY(p); sqrt(x * x + y * y) - radiusCm / 100.0 }
            FenceType.POLYGON -> {
                val fr = LocalFrame(vertices[0])
                val xy = vertices.map { fr.toXY(it) }
                val (px, py) = fr.toXY(p)
                var inside = false
                var dmin = Double.MAX_VALUE
                var j = xy.size - 1
                for (i in xy.indices) {
                    val (xi, yi) = xy[i]; val (xj, yj) = xy[j]
                    if (((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) inside = !inside
                    dmin = min(dmin, segDist(px, py, xj, yj, xi, yi))
                    j = i
                }
                if (inside) -dmin else dmin
            }
            FenceType.NONE -> Double.MAX_VALUE
        }
    }

    companion object {
        const val MAX_VERTICES = 24
        fun empty(slot: Int) = Fence(slot, FenceType.NONE, "")
        fun decodeBody(r: ByteReader): Fence? {
            val id = r.u8(); val type = FenceType.of(r.u8()); val name = r.str(16)
            val c = GeoPoint(r.i32(), r.i32()); val radius = r.u32(); val n = r.u8()
            if (n > MAX_VERTICES) return null
            val v = (0 until n).map { GeoPoint(r.i32(), r.i32()) }
            return if (r.ok) Fence(id, type, name, c, radius, v) else null
        }
        fun decodeBody(b: ByteArray): Fence? = decodeBody(ByteReader(b))
    }
}

class LocalFrame(ref: GeoPoint) {
    private val lat0 = ref.latE7 * 1e-7
    private val lon0 = ref.lonE7 * 1e-7
    private val ky = R * DEG
    private val kx = R * DEG * cos(lat0 * DEG)
    fun toXY(p: GeoPoint): Pair<Double, Double> {
        var dlon = p.lonE7 * 1e-7 - lon0
        if (dlon > 180) dlon -= 360
        if (dlon < -180) dlon += 360
        return Pair(dlon * kx, (p.latE7 * 1e-7 - lat0) * ky)
    }
    fun toPoint(x: Double, y: Double): GeoPoint = GeoPoint.of(lat0 + y / ky, lon0 + x / kx)
    companion object { const val R = 6371008.8; const val DEG = Math.PI / 180.0 }
}

fun haversineM(a: GeoPoint, b: GeoPoint): Double {
    val d = Math.PI / 180
    val la1 = a.lat * d; val la2 = b.lat * d
    val dla = la2 - la1; val dlo = (b.lon - a.lon) * d
    val h = sin(dla / 2) * sin(dla / 2) + cos(la1) * cos(la2) * sin(dlo / 2) * sin(dlo / 2)
    return 2 * LocalFrame.R * atan2(sqrt(h), sqrt(1 - h))
}

internal fun segDist(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double): Double {
    val vx = bx - ax; val vy = by - ay
    val l2 = vx * vx + vy * vy
    var t = if (l2 > 0) ((px - ax) * vx + (py - ay) * vy) / l2 else 0.0
    t = max(0.0, min(1.0, t))
    val dx = px - (ax + t * vx); val dy = py - (ay + t * vy)
    return sqrt(dx * dx + dy * dy)
}

internal fun segmentsIntersect(a: Pair<Double, Double>, b: Pair<Double, Double>, c: Pair<Double, Double>, d: Pair<Double, Double>): Boolean {
    fun orient(p: Pair<Double, Double>, q: Pair<Double, Double>, r: Pair<Double, Double>): Int {
        val v = (q.first - p.first) * (r.second - p.second) - (q.second - p.second) * (r.first - p.first)
        return if (abs(v) < 1e-12) 0 else if (v > 0) 1 else -1
    }
    fun onSeg(p: Pair<Double, Double>, q: Pair<Double, Double>, r: Pair<Double, Double>) =
        min(p.first, q.first) - 1e-9 <= r.first && r.first <= max(p.first, q.first) + 1e-9 &&
            min(p.second, q.second) - 1e-9 <= r.second && r.second <= max(p.second, q.second) + 1e-9
    val o1 = orient(a, b, c); val o2 = orient(a, b, d); val o3 = orient(c, d, a); val o4 = orient(c, d, b)
    if (o1 != o2 && o3 != o4) return true
    if (o1 == 0 && onSeg(a, b, c)) return true
    if (o2 == 0 && onSeg(a, b, d)) return true
    if (o3 == 0 && onSeg(c, d, a)) return true
    if (o4 == 0 && onSeg(c, d, b)) return true
    return false
}

/** Circle approximated by a polygon, only for drawing on the map. */
fun circleOutline(center: GeoPoint, radiusM: Double, n: Int = 72): List<GeoPoint> {
    val fr = LocalFrame(center)
    return (0 until n).map { i -> val a = 2 * Math.PI * i / n; fr.toPoint(radiusM * cos(a), radiusM * sin(a)) }
}
