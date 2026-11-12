package org.avoperformance.horse.core.license

import org.avoperformance.horse.core.identity.AvoUserCard
import org.junit.Assert.*
import org.junit.Test
import java.security.SecureRandom

class IssuerRegistryTest {
    private val rnd = SecureRandom()
    private val ana = AvoUserCard.generate("Ana Pérez · \"La Rubia\" | x", rnd)
    private val luis = AvoUserCard.generate("Luis", rnd)

    private fun sample() = IssuerRegistry()
        .upsert(RegUser(ana, 1000, phone = "+34 600 000 000", email = "ana@x.es", notes = "línea1\nlínea2"),
            RegEvent(1000, ana.code, RegEvent.Kind.ALTA))
        .upsert(RegUser(luis, 2000, rolesBits = LicenseRole.toBits(setOf(LicenseRole.PROPIETARIO)), expiresS = 9_999_999_999L / 10),
            RegEvent(2000, luis.code, RegEvent.Kind.ARCHIVO, LicenseRole.PROPIETARIO.bit, 999_999_999, "WhatsApp"))

    @Test fun roundTripKeepsEverything() {
        val r = sample()
        val back = IssuerRegistry.decode(r.encode())
        assertEquals(r.users.toSet(), back.users.toSet())
        assertEquals(r.events, back.events)
        assertEquals("línea1\nlínea2", back.user(ana.code)!!.notes)
        assertEquals(ana.secret, back.user(ana.code)!!.card.secret)
    }

    @Test fun searchByNameCodePhoneAndRole() {
        val r = sample()
        assertEquals(listOf(ana.code), r.search("rubia").map { it.code })
        assertEquals(listOf(luis.code), r.search(luis.code.takeLast(4)).map { it.code })
        assertEquals(listOf(ana.code), r.search("600 000").map { it.code })
        assertEquals(listOf(luis.code), r.search("propie").map { it.code })
        assertEquals(2, r.search("").size)
    }

    @Test fun upsertReplacesAndHistoryIsPerUser() {
        val r = sample().upsert(sample().user(ana.code)!!.copy(revoked = true), RegEvent(3000, ana.code, RegEvent.Kind.BAJA))
        assertEquals(2, r.users.size)
        assertTrue(r.user(ana.code)!!.revoked)
        assertEquals(listOf(RegEvent.Kind.BAJA, RegEvent.Kind.ALTA), r.history(ana.code).map { it.kind })
        assertEquals(ana.code, r.search("").last().code)     // given-up users go last
    }

    @Test fun damagedLineIsSkipped() {
        val text = sample().encode() + "U\tbasura\n"
        assertEquals(2, IssuerRegistry.decode(text).users.size)
    }

    @Test fun mergeKeepsNewestLicenceAndContacts() {
        val mine = sample()
        val older = IssuerRegistry().upsert(mine.user(luis.code)!!.copy(expiresS = 10, phone = "611"))
        val merged = mine.merge(older)
        assertEquals(mine.user(luis.code)!!.expiresS, merged.user(luis.code)!!.expiresS)
        val newer = IssuerRegistry().upsert(mine.user(ana.code)!!.copy(expiresS = 5_000_000_000L / 10, phone = ""))
        val m2 = mine.merge(newer)
        assertEquals(500_000_000L, m2.user(ana.code)!!.expiresS)
        assertEquals("+34 600 000 000", m2.user(ana.code)!!.phone)
    }

    @Test fun fullBackupWithKeyAndRegister() {
        val pair = LicenseCrypto.generateKeyPair(rnd)
        val pwd = "caballo-RTK-2026".toCharArray()
        val text = IssuerBackup.export(pair, sample(), pwd, rnd, iterations = 100_000)
        val r = IssuerBackup.import(text, pwd)
        assertArrayEquals(pair.public.encoded, r.key!!.public.encoded)
        assertEquals(sample().users.toSet(), r.registry.users.toSet())
        assertThrows(IllegalArgumentException::class.java) { IssuerBackup.import(text, "otra-contrasena".toCharArray()) }
        val noKey = IssuerBackup.import(IssuerBackup.export(null, sample(), pwd, rnd, iterations = 100_000), pwd)
        assertNull(noKey.key)
    }
}
