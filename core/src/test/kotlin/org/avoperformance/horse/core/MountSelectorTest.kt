package org.avoperformance.horse.core

import org.avoperformance.horse.core.ntrip.MountSelector
import org.avoperformance.horse.core.ntrip.SourceEntry
import org.junit.Assert.*
import org.junit.Test

class MountSelectorTest {
    // Test sourcetable with invented mountpoint names (real caster tables are fetched by the app)
    private val table = """
        SOURCETABLE 200 OK
        CAS;caster.test;2101;TEST;AVO;0;ESP;40.0;-3.0
        STR;BASE_A;Laredo;RTCM 3.2;1004(1),1012(1),1077(1),1087(1);2;GPS+GLO+GAL;TEST;ESP;43.41;-3.42;0;0;sNTRIP;none;B;N;2400;
        STR;BASE_B;Santander;RTCM 3.2;1077(1),1087(1);2;GPS+GLO+GAL;TEST;ESP;43.46;-3.80;0;0;sNTRIP;none;B;N;2400;
        STR;BASE_C;Bilbao;RTCM 3.3;1077(1);2;GPS+GAL;TEST;ESP;43.26;-2.93;0;0;sNTRIP;none;B;N;2400;
        STR;BASE_L1;Laredo L1;RTCM 3.2;1004(1);1;GPS;TEST;ESP;43.40;-3.43;0;0;sNTRIP;none;B;N;2400;
        STR;OLD_RTCM2;Laredo;RTCM 2.3;1(1);2;GPS;TEST;ESP;43.41;-3.42;0;0;sNTRIP;none;B;N;2400;
        STR;VRS3;Red;RTCM 3.2;1077(1);2;GPS+GLO+GAL;TEST;ESP;40.4;-3.7;1;1;sNTRIP;none;B;N;2400;
        STR;MADRID;Madrid;RTCM 3.2;1077(1);2;GPS+GAL;TEST;ESP;40.42;-3.70;0;0;sNTRIP;none;B;N;2400;
        ENDSOURCETABLE
    """.trimIndent()
    private val entries = SourceEntry.parseAll(table)
    private val laredo = 43.4120 to -3.4100      // El Regatón area
    private val burgos = 42.34 to -3.70          // > 20 km from every base (Laredo ≈ 120 km, Madrid ≈ 213 km)

    @Test fun parsesFields() {
        assertEquals(7, entries.size)
        val a = entries.first { it.mountpoint == "BASE_A" }
        assertEquals(43.41, a.lat!!, 1e-9); assertEquals(-3.42, a.lon!!, 1e-9)
        assertTrue(a.isRtcm3 && a.dualFrequency && !a.network && !a.nmea)
        assertFalse(entries.first { it.mountpoint == "OLD_RTCM2" }.isRtcm3)
        assertTrue(entries.first { it.mountpoint == "VRS3" }.let { it.network && it.nmea })
        assertNull(SourceEntry.parse("STR;con espacio;x;RTCM 3"))
        assertNull(SourceEntry.parse("CAS;caster;2101"))
    }

    @Test fun distanceIsCorrect() {
        // Laredo–Santander ≈ 31 km
        assertEquals(31.0, MountSelector.distanceKm(43.41, -3.42, 43.46, -3.80), 1.5)
        assertEquals(0.0, MountSelector.distanceKm(43.41, -3.42, 43.41, -3.42), 1e-9)
    }

    @Test fun nearestDualFrequencyBaseWins() {
        val c = MountSelector.choose(entries, laredo.first, laredo.second)!!
        assertEquals("BASE_A", c.main.mountpoint)                 // not the L1-only one, though it is as close
        assertTrue(c.distanceKm!! < 2)
        assertEquals("BASE_A", c.ordered.first())
        assertFalse("OLD_RTCM2" in c.ordered)
        assertTrue("VRS3" in c.ordered)                            // the network stays as last backup
    }

    @Test fun farFromEveryBaseUsesTheNetwork() {
        val c = MountSelector.choose(entries, burgos.first, burgos.second)!!
        assertEquals("VRS3", c.main.mountpoint)
        assertTrue(c.reason.contains("red"))
    }

    @Test fun withoutNetworkFarUsesNearestBaseAnyway() {
        val c = MountSelector.choose(entries.filterNot { it.network }, burgos.first, burgos.second)!!
        // nearest dual-frequency base (computed), never the L1-only one
        val expected = entries.filter { !it.network && it.isRtcm3 && !it.singleFrequency }
            .minBy { MountSelector.distanceKm(burgos.first, burgos.second, it.lat!!, it.lon!!) }.mountpoint
        assertEquals(expected, c.main.mountpoint)
        assertNotEquals("BASE_L1", c.main.mountpoint)
        assertTrue(c.distanceKm!! > 100)
        assertTrue(c.reason.contains("lejos"))
    }

    @Test fun hysteresisAvoidsBouncing() {
        // halfway between A and B, slightly closer to B: keep A while it is not clearly worse
        val mid = 43.44 to -3.62
        val fresh = MountSelector.choose(entries, mid.first, mid.second, maxBaseKm = 25)!!
        val kept = MountSelector.choose(entries, mid.first, mid.second, current = "BASE_A", maxBaseKm = 25)!!
        assertEquals("BASE_A", kept.main.mountpoint)
        assertTrue(fresh.main.mountpoint == "BASE_A" || fresh.main.mountpoint == "BASE_B")
        // at Santander, A (31 km) is clearly worse than B (~0 km): switch
        val sant = MountSelector.choose(entries, 43.46, -3.80, current = "BASE_A")!!
        assertEquals("BASE_B", sant.main.mountpoint)
    }

    @Test fun onNetworkABaseInsideTheLimitWins() {
        val c = MountSelector.choose(entries, laredo.first, laredo.second, current = "VRS3")!!
        assertEquals("BASE_A", c.main.mountpoint)
    }

    @Test fun nothingUsable() {
        assertNull(MountSelector.choose(entries.filter { !it.isRtcm3 }, laredo.first, laredo.second))
        assertNull(MountSelector.choose(emptyList(), 0.0, 0.0))
    }
}
