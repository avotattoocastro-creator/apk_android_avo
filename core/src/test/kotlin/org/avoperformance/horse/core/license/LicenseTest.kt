package org.avoperformance.horse.core.license

import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPair
import java.security.SecureRandom
import java.time.LocalDate
import java.time.ZoneId
import java.util.Base64
import org.avoperformance.horse.core.identity.AvoUserCard

class LicenseTest {
    private val rnd = SecureRandom()
    private val madrid = ZoneId.of("Europe/Madrid")
    private val uid = byteArrayOf(0x04, 0x5A, 0x11, 0x22, 0x33, 0x44, 0x55)
    private val code = "AVO-ABCD-EFGH"
    // 2026-10-27 12:00 UTC
    private val now = 1_793_102_400_000L
    private val pair: KeyPair = LicenseCrypto.generateKeyPair(rnd)
    private val trusted = listOf(pair.public)

    private fun issue(lastDay: LocalDate = LocalDate.of(2026, 12, 31), p: KeyPair = pair, u: ByteArray = uid) =
        LicenseIssuer.issue(p, u, code, now, lastDay, madrid, rnd)

    private fun clockAt(ms: Long) = LicenseClock.read(ms, 1_000, 7, null, null)

    @Test fun tokenRoundTripAndSize() {
        val t = issue()
        val bytes = t.encode()
        assertEquals(107, bytes.size)
        assertEquals(t, LicenseToken.decode(bytes))
        assertTrue(LicenseCrypto.verify(LicenseToken.decode(bytes), pair.public))
    }

    @Test fun expiryCoversWholeLastDayInMadrid() {
        val t = issue(LocalDate.of(2026, 12, 31))
        // 2027-01-01 00:00 Madrid = 2026-12-31 23:00 UTC
        assertEquals(java.time.Instant.parse("2026-12-31T23:00:00Z").epochSecond, t.expiresAtS)
        assertEquals(LocalDate.of(2026, 12, 31), LicenseIssuer.lastDayOf(t.expiresAtS, madrid))
    }

    @Test fun anyModifiedByteBreaksTheSignature() {
        val bytes = issue().encode()
        for (i in 0 until bytes.size - 64) {
            val m = bytes.copyOf(); m[i] = (m[i].toInt() xor 0x01).toByte()
            val decoded = runCatching { LicenseToken.decode(m) }.getOrNull() ?: continue
            assertFalse("byte $i", LicensePolicy.verifySignature(decoded, trusted))
        }
    }

    @Test fun laterExpiryWrittenByAnAttackerIsRejected() {
        val t = issue(LocalDate.of(2026, 11, 30))
        val forged = LicenseToken(t.keyId, t.uid, t.userCode, t.issuedAtS, t.expiresAtS + 365L * 86400, t.serial, t.flags, t.signature)
        val r = LicensePolicy.activate(forged.encode(), uid, code, "Ana", trusted, null, clockAt(now))
        assertTrue(r is ActivationResult.Refused)
    }

    @Test fun licenceSignedWithAnotherKeyIsRejected() {
        val other = LicenseCrypto.generateKeyPair(rnd)
        val r = LicensePolicy.activate(issue(p = other).encode(), uid, code, "Ana", trusted, null, clockAt(now))
        assertTrue((r as ActivationResult.Refused).reason.contains("firma"))
    }

    @Test fun copyToAnotherCardIsRejected() {
        val r = LicensePolicy.activate(issue().encode(), byteArrayOf(0x04, 1, 2, 3, 4, 5, 6), code, "Ana", trusted, null, clockAt(now))
        assertTrue((r as ActivationResult.Refused).reason.contains("copia"))
    }

    @Test fun userCodeMustMatchTheCard() {
        val r = LicensePolicy.activate(issue().encode(), uid, "AVO-ZZZZ-ZZZZ", "Ana", trusted, null, clockAt(now))
        assertTrue(r is ActivationResult.Refused)
    }

    @Test fun validCardActivatesAndStatusFollowsTheDate() {
        val r = LicensePolicy.activate(issue(LocalDate.of(2026, 11, 2)).encode(), uid, code, "Ana", trusted, null, clockAt(now))
        val stored = (r as ActivationResult.Activated).stored
        val active = LicensePolicy.status(stored, trusted, now) as LicenseStatus.Active
        assertTrue(active.expiringSoon)          // 27/10 → 2/11 inclusive
        assertEquals(7, active.daysLeft)
        assertTrue(active.fullAccess)
        val far = LicensePolicy.status(stored, trusted, now - 30L * 86_400_000) as LicenseStatus.Active
        assertFalse(far.expiringSoon)
        val expired = LicensePolicy.status(stored, trusted, stored.token.expiresAtMs)
        assertTrue(expired is LicenseStatus.Expired)
        assertFalse(expired.fullAccess)
    }

    @Test fun expiredCardCannotBeActivated() {
        val t = issue(LocalDate.of(2026, 11, 2))
        val r = LicensePolicy.activate(t.encode(), uid, code, "Ana", trusted, null, clockAt(t.expiresAtMs + 1))
        assertTrue(r is ActivationResult.Refused)
    }

    @Test fun renewalAndNoDowngrade() {
        val short = issue(LocalDate.of(2026, 11, 30))
        val long = issue(LocalDate.of(2027, 6, 30))
        val s1 = (LicensePolicy.activate(short.encode(), uid, code, "Ana", trusted, null, clockAt(now)) as ActivationResult.Activated).stored
        val r2 = LicensePolicy.activate(long.encode(), uid, code, "Ana", trusted, s1, clockAt(now))
        assertTrue((r2 as ActivationResult.Activated).renewed)
        val back = LicensePolicy.activate(short.encode(), uid, code, "Ana", trusted, r2.stored, clockAt(now))
        assertTrue(back is ActivationResult.Refused)
        assertTrue(LicensePolicy.activate(long.encode(), uid, code, "Ana", trusted, r2.stored, clockAt(now)) is ActivationResult.AlreadyActive)
    }

    @Test fun noTrustedKeysMeansNotEnforced() {
        assertEquals(LicenseStatus.NotEnforced, LicensePolicy.status(null, emptyList(), now))
        assertTrue(LicensePolicy.activate(issue().encode(), uid, code, "Ana", emptyList(), null, clockAt(now)) is ActivationResult.Refused)
        assertEquals(LicenseStatus.None, LicensePolicy.status(null, trusted, now))
    }

    @Test fun keyRemovedFromTheAppInvalidatesStoredLicence() {
        val stored = (LicensePolicy.activate(issue().encode(), uid, code, "Ana", trusted, null, clockAt(now)) as ActivationResult.Activated).stored
        val newKey = LicenseCrypto.generateKeyPair(rnd).public
        assertTrue(LicensePolicy.status(stored, listOf(newKey), now) is LicenseStatus.Invalid)
    }

    @Test fun storedLicenceRoundTrip() {
        val stored = (LicensePolicy.activate(issue().encode(), uid, code, "José Ñúñez | x", trusted, null, clockAt(now)) as ActivationResult.Activated).stored
        assertEquals(stored, StoredLicense.decode(stored.encode()))
    }

    @Test fun trustedKeyListParsing() {
        val k2 = LicenseCrypto.generateKeyPair(rnd).public
        val text = " ${LicenseCrypto.publicKeyToBase64(pair.public)},\n ${LicenseCrypto.publicKeyToBase64(k2)} "
        val keys = LicenseCrypto.parseTrustedKeys(text)
        assertEquals(2, keys.size)
        assertArrayEquals(pair.public.encoded, keys[0].encoded)
        assertTrue(LicenseCrypto.parseTrustedKeys("").isEmpty())
        assertTrue(LicenseCrypto.parseTrustedKeys(null).isEmpty())
        assertThrows(Exception::class.java) { LicenseCrypto.parseTrustedKeys("QUJD") }
    }

    @Test fun derRawConversionRoundTrip() {
        repeat(200) {
            val raw = ByteArray(64).also(rnd::nextBytes)
            if (it % 3 == 0) { raw[0] = 0; raw[32] = 0 }        // short integers
            if (it % 5 == 0) { raw[0] = 0x80.toByte(); raw[32] = 0xFF.toByte() }   // high bit set
            assertArrayEquals(raw, LicenseCrypto.derToRaw(LicenseCrypto.rawToDer(raw)))
        }
    }

    // ---- clock

    @Test fun clockCannotGoBackwards() {
        val first = LicenseClock.read(now, 50_000, 3, null, null)
        assertEquals(now, first.effectiveMs)
        // user moves the clock back 60 days, same boot, 10 s later
        val back = LicenseClock.read(now - 60L * 86_400_000, 60_000, 3, null, first.record)
        assertEquals(now + 10_000, back.effectiveMs)
        assertTrue(back.systemClockBehind)
        // after a reboot, the high-water mark still holds
        val reboot = LicenseClock.read(now - 60L * 86_400_000, 5_000, 4, null, back.record)
        assertEquals(now + 10_000, reboot.effectiveMs)
        // time keeps moving forward from the anchor (the 10 s gained by the rollback guard are kept)
        val later = LicenseClock.read(now + 3_600_000, 3_605_000, 4, null, reboot.record)
        assertEquals(now + 3_610_000, later.effectiveMs)
        assertFalse(later.systemClockBehind)
    }

    @Test fun networkTimeIsAuthoritativeAndRepairsAFutureClock() {
        val wrong = LicenseClock.read(now + 400L * 86_400_000, 1_000, 1, null, null)     // clock set a year ahead by mistake
        val fixed = LicenseClock.read(now, 2_000, 1, now, wrong.record)
        assertEquals(now, fixed.effectiveMs)
        assertEquals(now, fixed.record.highWaterMs)
        assertEquals("red", fixed.source)
    }

    @Test fun expiredByClockRollbackStaysExpired() {
        val t = issue(LocalDate.of(2026, 11, 2))
        val stored = (LicensePolicy.activate(t.encode(), uid, code, "Ana", trusted, null, clockAt(now)) as ActivationResult.Activated).stored
        val after = LicenseClock.read(t.expiresAtMs + 1, 9_000, 7, null, stored.clock)
        val rolledBack = LicenseClock.read(now, 9_500, 7, null, after.record)
        assertTrue(LicensePolicy.status(stored, trusted, rolledBack.effectiveMs) is LicenseStatus.Expired)
    }

    // ---- key backup

    @Test fun keyBackupRoundTrip() {
        val pwd = "caballo-RTK-2026".toCharArray()
        val text = LicenseKeyBackup.export(pair, pwd, rnd, iterations = 100_000)
        assertTrue(text.startsWith(LicenseKeyBackup.HEADER))
        val back = LicenseKeyBackup.import(text, pwd)
        assertArrayEquals(pair.public.encoded, back.public.encoded)
        val t = LicenseIssuer.issue(back, uid, code, now, LocalDate.of(2027, 1, 31), madrid, rnd)
        assertTrue(LicenseCrypto.verify(t, pair.public))
    }

    @Test fun keyBackupWrongPasswordOrTampered() {
        val text = LicenseKeyBackup.export(pair, "caballo-RTK-2026".toCharArray(), rnd, iterations = 100_000)
        val e = assertThrows(IllegalArgumentException::class.java) { LicenseKeyBackup.import(text, "otra-contrasena".toCharArray()) }
        assertTrue(e.message!!.contains("Contraseña"))
        val lines = text.trim().lines()
        val blob = Base64.getMimeDecoder().decode(lines.drop(1).joinToString(""))
        blob[blob.size - 20] = (blob[blob.size - 20].toInt() xor 1).toByte()
        val tampered = lines[0] + "\n" + Base64.getEncoder().encodeToString(blob)
        assertThrows(IllegalArgumentException::class.java) { LicenseKeyBackup.import(tampered, "caballo-RTK-2026".toCharArray()) }
        assertThrows(IllegalArgumentException::class.java) { LicenseKeyBackup.export(pair, "corta".toCharArray()) }
    }

    // ---- licence sent as a file (email / WhatsApp)

    private val card = AvoUserCard(code, "Ana", "0123456789abcdef0123456789abcdef")

    private fun remote(lastDay: LocalDate = LocalDate.of(2027, 3, 31)) =
        LicenseIssuer.issue(pair, byteArrayOf(0), code, now, lastDay, madrid, rnd, remote = true)

    @Test fun fileRoundTripActivatesTheRightUser() {
        val text = LicenseFile.encode(remote(), card, rnd)
        assertTrue(LicenseFile.looksLikeLicenseFile(text.toByteArray()))
        assertEquals(code, LicenseFile.userCodeOf(text))
        val bytes = LicenseFile.decode(text, card)
        val r = LicensePolicy.activateFromFile(bytes, card.code, "Ana", trusted, null, clockAt(now))
        assertTrue(r is ActivationResult.Activated)
    }

    @Test fun fileForwardedToAnotherPhoneCannotBeOpened() {
        val text = LicenseFile.encode(remote(), card, rnd)
        val sameCodeOtherSecret = AvoUserCard(code, "Ana", "ffffffffffffffffffffffffffffffff")
        assertThrows(IllegalArgumentException::class.java) { LicenseFile.decode(text, sameCodeOtherSecret) }
        val otherUser = AvoUserCard("AVO-ZZZZ-ZZZZ", "Luis", card.secret)
        assertThrows(IllegalArgumentException::class.java) { LicenseFile.decode(text, otherUser) }
    }

    @Test fun editedFileIsRejected() {
        val text = LicenseFile.encode(remote(), card, rnd)
        val lines = text.trim().lines()
        val blob = Base64.getDecoder().decode(lines[2]); blob[20] = (blob[20].toInt() xor 1).toByte()
        val edited = "${lines[0]}\n${lines[1]}\n${Base64.getEncoder().encodeToString(blob)}"
        assertThrows(IllegalArgumentException::class.java) { LicenseFile.decode(edited, card) }
    }

    @Test fun cardLicenceCannotBeUsedAsFileAndFileNeedsItsUser() {
        val cardToken = issue().encode()
        assertTrue(LicensePolicy.activateFromFile(cardToken, code, "Ana", trusted, null, clockAt(now)) is ActivationResult.Refused)
        assertThrows(IllegalArgumentException::class.java) { LicenseFile.encode(issue(), card, rnd) }
        assertTrue(LicensePolicy.activateFromFile(remote().encode(), "AVO-ZZZZ-ZZZZ", "Luis", trusted, null, clockAt(now)) is ActivationResult.Refused)
    }

    @Test fun fileRenewsAnExpiredCardLicence() {
        val t = issue(LocalDate.of(2026, 11, 2))
        val stored = (LicensePolicy.activate(t.encode(), uid, code, "Ana", trusted, null, clockAt(now)) as ActivationResult.Activated).stored
        val later = clockAt(t.expiresAtMs + 86_400_000)
        assertTrue(LicensePolicy.status(stored, trusted, later.effectiveMs) is LicenseStatus.Expired)
        val renewed = LicenseIssuer.issue(pair, byteArrayOf(0), code, t.expiresAtMs, LocalDate.of(2027, 6, 30), madrid, rnd, remote = true)
        val r = LicensePolicy.activateFromFile(LicenseFile.decode(LicenseFile.encode(renewed, card, rnd), card), code, "Ana", trusted, stored, later)
        val s2 = (r as ActivationResult.Activated).stored
        assertTrue(LicensePolicy.status(s2, trusted, later.effectiveMs) is LicenseStatus.Active)
    }
}
