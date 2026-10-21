package org.avoperformance.horse.maps

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SatelliteTileUrlTest {
    @Test fun arcgisUsesZoomRowColumnOrder() {
        assertEquals(SatelliteTileUrl.ROOT + "3/4/6", SatelliteTileUrl.build(3, 6, 4))
        assertEquals(SatelliteTileUrl.ROOT + "0/0/0", SatelliteTileUrl.build(0, 0, 0))
    }

    @Test fun invalidZoomAndTileIndicesAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { SatelliteTileUrl.build(-1, 0, 0) }
        assertThrows(IllegalArgumentException::class.java) { SatelliteTileUrl.build(20, 0, 0) }
        assertThrows(IllegalArgumentException::class.java) { SatelliteTileUrl.build(2, 4, 1) }
        assertThrows(IllegalArgumentException::class.java) { SatelliteTileUrl.build(2, 2, -1) }
    }

    @Test fun supportedHighestZoomFitsIntTileIndex() {
        assertEquals(SatelliteTileUrl.ROOT + "19/524287/524287",
            SatelliteTileUrl.build(19, 524287, 524287))
    }
}
