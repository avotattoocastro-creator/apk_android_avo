package org.avoperformance.horse.core.license

import org.avoperformance.horse.core.identity.AvoUserCard
import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPair
import java.security.SecureRandom
import java.time.LocalDate
import java.time.ZoneId

/** «Activar móvil por NFC»: APDU exchange (card ↔ reader loopback) and the device-bound licence policy. */
class NfcActivationTest {
    private val rnd = SecureRandom()
    private val madrid = ZoneId.of("Europe/Madrid")
    private val now = 1_793_102_400_000L   // 2026-10-27 12:00 UTC
    private val pair: KeyPair = LicenseCrypto.generateKeyPair(rnd)
    private val trusted = listOf(pair.public)
    private val user = AvoUserCard.generate("María José Núñez-Ibáñez de la Peña", rnd)
    private val phoneA = NfcActivation.deviceId("a1b2c3d4e5f60718", "org.avoperformance.horse")
    private val phoneB = NfcActivation.deviceId("ffeeddccbbaa9988", "org.avoperformance.horse")

    private fun clockAt(ms: Long) = LicenseClock.read(ms, 1_000, 7, null, null)

    private fun card(armed: Boolean = true, roles: Set<LicenseRole> = setOf(LicenseRole.JINETE, LicenseRole.ENTRENADOR)) =
        NfcActivation.Card(issue = { id ->
            if (!armed) null
            else NfcActivation.Result(user, LicenseIssuer.issueForDevice(pair, id, user.code, now, LocalDate.of(2027, 6, 30), madrid, roles, rnd).encode())
        }, armed = { armed })

    @Test fun deviceIdIsStableAndPerPhone() {
        assertEquals(NfcActivation.DEVICE_ID_LEN, phoneA.size)
        assertArrayEquals(phoneA, NfcActivation.deviceId("a1b2c3d4e5f60718", "org.avoperformance.horse"))
        assertFalse(phoneA.contentEquals(phoneB))
    }

    @Test fun loopbackExchangeActivatesThatPhone() {
        val c = card()
        val out = NfcActivation.read({ c.process(it) }, phoneA)
        assertTrue(out.toString(), out is NfcActivation.Outcome.Received)
        val r = (out as NfcActivation.Outcome.Received).result
        assertEquals(user, r.card)   // the identity (with its secret) travels too, long name included (several READ chunks)
        val token = LicenseToken.decode(r.token)
        assertTrue(token.isDeviceBound)
        assertArrayEquals(phoneA, token.uid)
        assertEquals(setOf(LicenseRole.JINETE, LicenseRole.ENTRENADOR), token.roleSet)
        val a = LicensePolicy.activateOnDevice(r.token, phoneA, r.card.code, r.card.name, trusted, null, clockAt(now))
        assertTrue(a.toString(), a is ActivationResult.Activated)
    }

    @Test fun licenceOfOnePhoneIsRefusedOnAnother() {
        val c = card()
        val r = (NfcActivation.read({ c.process(it) }, phoneA) as NfcActivation.Outcome.Received).result
        val a = LicensePolicy.activateOnDevice(r.token, phoneB, r.card.code, r.card.name, trusted, null, clockAt(now))
        assertTrue(a is ActivationResult.Refused)
    }

    @Test fun deviceLicenceIsRefusedOnACardAndAsAFile() {
        val t = LicenseIssuer.issueForDevice(pair, phoneA, user.code, now, LocalDate.of(2027, 1, 31), madrid, setOf(LicenseRole.JINETE), rnd)
        // even a "card" whose UID equals the device id
        assertTrue(LicensePolicy.activate(t.encode(), phoneA, user.code, user.name, trusted, null, clockAt(now)) is ActivationResult.Refused)
        assertTrue(LicensePolicy.activateFromFile(t.encode(), user.code, user.name, trusted, null, clockAt(now)) is ActivationResult.Refused)
    }

    @Test fun cardOrFileLicenceIsRefusedAsADeviceLicence() {
        val cardToken = LicenseIssuer.issue(pair, phoneA, user.code, now, LocalDate.of(2027, 1, 31), madrid, setOf(LicenseRole.JINETE), rnd)
        assertTrue(LicensePolicy.activateOnDevice(cardToken.encode(), phoneA, user.code, user.name, trusted, null, clockAt(now)) is ActivationResult.Refused)
    }

    @Test fun otherUserOrOtherKeyIsRefused() {
        val t = LicenseIssuer.issueForDevice(pair, phoneA, user.code, now, LocalDate.of(2027, 1, 31), madrid, setOf(LicenseRole.JINETE), rnd)
        assertTrue(LicensePolicy.activateOnDevice(t.encode(), phoneA, "AVO-ZZZZ-ZZZZ", "Otro", trusted, null, clockAt(now)) is ActivationResult.Refused)
        val other = LicenseCrypto.generateKeyPair(rnd)
        val t2 = LicenseIssuer.issueForDevice(other, phoneA, user.code, now, LocalDate.of(2027, 1, 31), madrid, setOf(LicenseRole.JINETE), rnd)
        assertTrue(LicensePolicy.activateOnDevice(t2.encode(), phoneA, user.code, user.name, trusted, null, clockAt(now)) is ActivationResult.Refused)
    }

    @Test fun notArmedAndNotAvo() {
        assertEquals(NfcActivation.Outcome.NotArmed, NfcActivation.read({ card(armed = false).process(it) }, phoneA))
        // another HCE app / payment card: SELECT of our AID is not found
        assertEquals(NfcActivation.Outcome.NotAvo, NfcActivation.read({ byteArrayOf(0x6A, 0x82.toByte()) }, phoneA))
        // the link breaks
        assertEquals(NfcActivation.Outcome.NotAvo, NfcActivation.read({ throw java.io.IOException("Tag was lost") }, phoneA))
    }

    @Test fun cardRejectsMalformedCommands() {
        val c = card()
        assertArrayEquals(NfcActivation.SW_NOT_FOUND, c.process(NfcActivation.activateApdu(phoneA)))   // not selected
        c.process(NfcActivation.selectApdu())
        assertArrayEquals(NfcActivation.SW_NOT_ARMED, c.process(NfcActivation.readApdu(0, 10)))        // nothing issued yet
        assertArrayEquals(NfcActivation.SW_INS, c.process(byteArrayOf(0x80.toByte(), 0x55, 0, 0)))
        assertArrayEquals(NfcActivation.SW_WRONG_LENGTH, c.process(byteArrayOf(0x80.toByte(), NfcActivation.INS_ACTIVATE, 0, 0, 9, 1, 2)))
    }

    @Test fun resultRoundTrip() {
        val r = NfcActivation.Result(user, byteArrayOf(1, 2, 3))
        assertEquals(r, NfcActivation.Result.decode(r.encode()))
    }
}
