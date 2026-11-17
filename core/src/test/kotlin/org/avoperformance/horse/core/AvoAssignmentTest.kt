package org.avoperformance.horse.core

import org.avoperformance.horse.core.share.AvoAssignment
import org.junit.Assert.*
import org.junit.Test

/** AVO-ASSIGN-1 (docs/ASIGNACION_CABALLO.md): rules shared with Windows, iPad and the C++ engine. */
class AvoAssignmentTest {
    private val t1 = AvoAssignment.parseIso("2026-11-12T22:00:00Z")

    @Test fun blockJsonFollowsTheContract() {
        val a = AvoAssignment("H_ZAKINA", "Zakina", "AVO-A66T-F2E9", "Andoni \"Lezama\"", t1, "android", rawHorse = "HORSE_001")
        assertEquals(
            "{\"version\":1,\"horseCode\":\"H_ZAKINA\",\"horseName\":\"Zakina\",\"riderCode\":\"AVO-A66T-F2E9\",\"riderName\":\"Andoni \\\"Lezama\\\"\"," +
                "\"actualizadoUtc\":\"2026-11-12T22:00:00Z\",\"app\":\"android\",\"raw\":{\"horseCode\":\"HORSE_001\",\"riderCode\":null}}",
            a.toJson())
    }

    @Test fun fromFieldsRoundTripAndEmptyBlock() {
        val m = mapOf("horseCode" to "H_ZAKINA", "horseName" to " Zakina ", "actualizadoUtc" to "2026-11-12T22:00:00Z", "app" to "windows")
        val a = AvoAssignment.fromFields({ m[it] }, { if (it == "horseCode") "HORSE_001" else null })!!
        assertEquals("Zakina", a.horseName); assertEquals(t1, a.updatedUtcMs); assertEquals("HORSE_001", a.rawHorse); assertNull(a.riderCode)
        assertNull(AvoAssignment.fromFields({ if (it == "app") "ipad" else null }))            // only metadata: no assignment
        assertEquals(0L, AvoAssignment.parseIso("no es una fecha"))
    }

    @Test fun blockWinsOverTopLevelFields() {
        val block = AvoAssignment("H_ZAKINA", "Zakina", null, null, t1, "ipad")
        val id = AvoAssignment.resolve(block, "HORSE_001", "Power Gold", "AVO-A66T-F2E9", "Andoni")
        assertEquals("H_ZAKINA", id.horseCode); assertEquals("Zakina", id.horseName)
        assertEquals("AVO-A66T-F2E9", id.riderCode); assertEquals("Andoni", id.riderName)     // not in the block: top level
        assertEquals("Power Gold", AvoAssignment.resolve(null, "", "Power Gold", null, null).horseName)
        assertNull(AvoAssignment.resolve(null, " ", "", null, null).horseCode)
    }

    @Test fun newerAssignmentWinsOnReimport() {
        val file = AvoAssignment("H_MALWINA", "Malwina", null, null, t1, "windows")
        assertTrue(AvoAssignment.fileWins(file, "H_ZAKINA", t1 - 1))      // file newer than the local change
        assertFalse(AvoAssignment.fileWins(file, "H_ZAKINA", t1 + 1))     // local change newer
        assertFalse(AvoAssignment.fileWins(null, "H_ZAKINA", 0))          // old file never overrides an assigned horse
        assertTrue(AvoAssignment.fileWins(null, null, t1))                // nothing assigned here yet
    }

    @Test fun engineOptionSkipsEmptyValues() {
        assertEquals("\"asignacion\":{\"horseCode\":\"H_ZAKINA\",\"riderName\":\"Andoni\"}",
            AvoAssignment.engineOption("H_ZAKINA", " ", null, "Andoni"))
        assertNull(AvoAssignment.engineOption(null, "", " ", null))
    }

    @Test fun watchIdentityCheckBeforeRecording() {
        assertTrue(AvoAssignment.watchNeedsIdentity("HORSE_001", "AVO-A66T-F2E9", "H_ZAKINA", "AVO-A66T-F2E9"))
        assertFalse(AvoAssignment.watchNeedsIdentity("H_ZAKINA", "AVO-A66T-F2E9", "H_ZAKINA", "AVO-A66T-F2E9"))
        assertFalse(AvoAssignment.watchNeedsIdentity("HORSE_001", "", null, null))   // nothing chosen: nothing to send
        assertTrue(AvoAssignment.watchNeedsIdentity(null, null, null, "RIDER_002"))
    }
}
