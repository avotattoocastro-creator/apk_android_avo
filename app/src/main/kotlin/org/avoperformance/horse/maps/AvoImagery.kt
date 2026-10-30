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

    /** Place names and roads drawn over the imagery (Hybrid view). */
    private fun reference(name: String, service: String) = object : OnlineTileSourceBase(
        name, 0, 19, 256, ".png", arrayOf("https://server.arcgisonline.com/ArcGIS/rest/services/Reference/$service/MapServer/tile/"),
    ) {
        override fun getTileURLString(pMapTileIndex: Long): String {
            val z = MapTileIndex.getZoom(pMapTileIndex); val x = MapTileIndex.getX(pMapTileIndex); val y = MapTileIndex.getY(pMapTileIndex)
            return baseUrl + z + "/" + y + "/" + x
        }
    }
    val roadsSource = reference("AVO_ESRI_TRANSPORT", "World_Transportation")
    val placesSource = reference("AVO_ESRI_PLACES", "World_Boundaries_and_Places")
}
