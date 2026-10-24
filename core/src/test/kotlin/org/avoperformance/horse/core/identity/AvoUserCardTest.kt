package org.avoperformance.horse.core.identity

import org.junit.Assert.*
import org.junit.Test
import java.security.SecureRandom

class AvoUserCardTest {
    @Test fun roundTripWithAccentsAndSpaces() {
        val c = AvoUserCard.generate("José Ñúñez & Hijos", SecureRandom())
        val back = AvoUserCard.parse(c.toUri())
        assertEquals(c, back)
        assertTrue(c.toUri().startsWith("avohorse://identity/user/AVO-"))
    }

    @Test fun uniqueCodes() {
        val r = SecureRandom()
        assertEquals(500, (1..500).map { AvoUserCard.generate("A", r).code }.toSet().size)
    }

    @Test fun fitsTags() {
        // NTAG215 (504 B NDEF): worst case, 40 accented characters, plus AAR record (~35 B).
        assertTrue(AvoUserCard.generate("Ñ".repeat(AvoUserCard.MAX_NAME)).toUri().length + 40 < 504)
        // NTAG213 (137 B) is NOT guaranteed: the AVO Tarjetas app checks the real capacity before writing.
    }

    @Test fun secretNotInToString() {
        val c = AvoUserCard.generate("Ana")
        assertFalse(c.toString().contains(c.secret))
    }

    @Test fun rejectsHorseRiderAndBadInput() {
        assertFalse(AvoUserCard.isUserUri("avohorse://identity/horse/H1?v=2&name=x"))
        assertThrows(IllegalArgumentException::class.java) { AvoUserCard.parse("avohorse://identity/user/AVO-AAAA-AAAA?v=2&name=a&k=" + "0".repeat(32)) }
        assertThrows(IllegalArgumentException::class.java) { AvoUserCard.parse("avohorse://identity/user/AVO-AAAA-AAAA?v=1&name=a&k=123") }
        assertThrows(IllegalArgumentException::class.java) { AvoUserCard.parse("avohorse://identity/user/AVO-0000-AAAA?v=1&name=a&k=" + "0".repeat(32)) }
        assertThrows(IllegalArgumentException::class.java) { AvoUserCard.parse("avohorse://identity/user/AVO-AAAA-AAAA?v=1&name=&k=" + "0".repeat(32)) }
    }
}
