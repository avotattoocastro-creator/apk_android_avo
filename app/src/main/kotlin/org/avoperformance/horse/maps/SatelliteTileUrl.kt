package org.avoperformance.horse.maps

/**
 * Esri World Imagery REST tiles use /tile/{z}/{y}/{x}, NOT the XYZ order
 * /{z}/{x}/{y}. Input validation prevents accidental requests to invalid zooms.
 */
object SatelliteTileUrl {
    const val ROOT = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/"

    fun build(z: Int, x: Int, y: Int): String {
        require(z in 0..19) { "Zoom fuera de rango" }
        val upperExclusive = 1L shl z
        require(x >= 0 && y >= 0 && x.toLong() < upperExclusive && y.toLong() < upperExclusive) {
            "Índice de tesela fuera de rango"
        }
        return ROOT + z + "/" + y + "/" + x
    }
}
