package org.avoperformance.horse.maps

import org.osmdroid.util.MapTileIndex
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase

/**
 * Esri World Imagery in Web Mercator. Esri basemap services require compliant
 * use and visible attribution to Esri and imagery contributors.
 * No API keys, secrets, or paid-service credentials are embedded here.
 */
object AvoImagery {
    const val ATTRIBUTION = "Imágenes: © Esri, Maxar, Earthstar Geographics y GIS User Community"
    val tileSource = object : OnlineTileSourceBase(
        "AVO_ESRI_WORLD_IMAGERY",
        0, 19, 256, ".jpg",
        arrayOf(SatelliteTileUrl.ROOT),
    ) {
        override fun getTileURLString(pMapTileIndex: Long): String = SatelliteTileUrl.build(
            MapTileIndex.getZoom(pMapTileIndex),
            MapTileIndex.getX(pMapTileIndex),
            MapTileIndex.getY(pMapTileIndex),
        )
    }
}
