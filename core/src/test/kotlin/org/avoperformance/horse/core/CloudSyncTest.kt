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
        // vector compartido con ipad/AVOiPadTests/CloudStorageTests.swift y windows/AVO.Windows.SelfTest/CloudTests.cs
        assertEquals("a242c37ddf781698761028f9ea2c649f", a)
    }

    @Test fun pendientesYRegistro() {
        val c = listOf(CloudSync.Candidate("S1", "f1", 10), CloudSync.Candidate("S2", "f2", 30), CloudSync.Candidate("S3", "f3", 20))
        val done = mapOf("S1" to "f1", "S3" to "viejo")
        assertEquals(listOf("S2", "S3"), CloudSync.pending(c, done).map { it.sessionId })
        assertEquals(done, CloudSync.decode(CloudSync.encode(done)))
        assertEquals(emptyMap<String, String>(), CloudSync.decode(null))
    }

    @Test fun ganaLaAsignacionMasReciente() {
        val A = CloudSync.Action
        fun r(fp: String?, ms: Long, h: String? = "LEZAMA", rd: String? = "Ana") = CloudSync.Remote(fp, ms, "H1", h, "R1", rd)
        // sin copia en la nube: se sube si está completo
        assertEquals(A.UPLOAD, CloudSync.decide("f1", 0, "LEZAMA", "Ana", null))
        assertEquals(A.NOTHING, CloudSync.decide(null, 0, null, null, null))
        // misma huella: nada
        assertEquals(A.NOTHING, CloudSync.decide("f1", 10, "LEZAMA", "Ana", r("f1", 10)))
        // el iPad la cambió después: se aplica aquí, no se pisa
        assertEquals(A.APPLY_REMOTE, CloudSync.decide("f1", 10, "OTRO", "Ana", r("f2", 20)))
        // aquí se cambió después: se sube
        assertEquals(A.UPLOAD, CloudSync.decide("f3", 30, "OTRO", "Eva", r("f2", 20)))
        // aquí no tiene caballo: se toma el de la nube
        assertEquals(A.APPLY_REMOTE, CloudSync.decide(null, 0, null, null, r("f2", 0)))
        // la nube es más nueva pero dice lo mismo (huella de otra app): nada
        assertEquals(A.NOTHING, CloudSync.decide("f1", 10, "lezama", "ana", r("fX", 20)))
    }
}
