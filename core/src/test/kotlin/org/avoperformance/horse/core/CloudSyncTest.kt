package org.avoperformance.horse.core

import org.avoperformance.horse.core.cloud.CloudSync
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nube AVO: rutas y huellas (las mismas reglas que firebase/storage.rules y las apps iPad y Windows). */
class CloudSyncTest {
    private val safe = Regex("^[A-Za-z0-9._-]{1,140}[.]avo$")

    @Test fun rutaSegura() {
        assertEquals("trainings/AVO-ABCD-EF23/AVO_S20261120_0001.avo", CloudSync.path("avo-abcd-ef23", "S20261120_0001"))
        assertEquals("AVO_a_b_c_.avo", CloudSync.fileName("a/b c."))
        assertTrue(safe.matches(CloudSync.fileName("x".repeat(400))))
        assertTrue(safe.matches(CloudSync.fileName("ñandú/../../x")))
    }

    @Test fun huellaCambiaAlReasignar() {
        val a = CloudSync.fingerprint("AB", "HORSE_001", "RIDER_001", "LEZAMA", "Ana")
        assertEquals(a, CloudSync.fingerprint("ab", "HORSE_001", "RIDER_001", "LEZAMA", "Ana"))
        assertNotEquals(a, CloudSync.fingerprint("ab", "HORSE_002", "RIDER_001", "LEZAMA", "Ana"))
        assertNotEquals(a, CloudSync.fingerprint("ab", "HORSE_001", "RIDER_001", "LEZAMA", "Eva"))
        assertEquals(32, a.length)
    }

    @Test fun pendientesYRegistro() {
        val c = listOf(CloudSync.Candidate("S1", "f1", 10), CloudSync.Candidate("S2", "f2", 30), CloudSync.Candidate("S3", "f3", 20))
        val done = mapOf("S1" to "f1", "S3" to "viejo")
        assertEquals(listOf("S2", "S3"), CloudSync.pending(c, done).map { it.sessionId })
        assertEquals(done, CloudSync.decode(CloudSync.encode(done)))
        assertEquals(emptyMap<String, String>(), CloudSync.decode(null))
    }
}
