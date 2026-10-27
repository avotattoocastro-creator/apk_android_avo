package org.avoperformance.horse.core.license

import java.security.KeyPair
import java.security.SecureRandom
import java.time.LocalDate
import java.time.ZoneId

/** Issues licences (used by AVO Tarjetas). */
object LicenseIssuer {
    /** "Activa hasta [lastDay]" includes the whole day: expiry = 00:00 of the next day in [zone]. */
    fun expiryForLastDay(lastDay: LocalDate, zone: ZoneId): Long = lastDay.plusDays(1).atStartOfDay(zone).toEpochSecond()

    /** Last day included by an expiry produced by [expiryForLastDay]. */
    fun lastDayOf(expiresAtS: Long, zone: ZoneId): LocalDate =
        java.time.Instant.ofEpochSecond(expiresAtS - 1).atZone(zone).toLocalDate()

    /**
     * [tagUid]: UID of the card. For a licence sent as a file ([remote]) it is the card's UID when known
     * (informative); the file is bound to the user by the card secret instead (see [LicenseFile]).
     * [roles]: at least one; they decide the functions of the app ([LicenseFeatures]).
     */
    fun issue(pair: KeyPair, tagUid: ByteArray, userCode: String, nowMs: Long, lastDay: LocalDate, zone: ZoneId,
              roles: Set<LicenseRole>, random: SecureRandom = SecureRandom(), remote: Boolean = false): LicenseToken {
        require(roles.isNotEmpty()) { "Marca al menos un rol" }
        val expires = expiryForLastDay(lastDay, zone)
        val issued = nowMs / 1000
        require(expires > issued) { "La fecha de activación ya ha pasado" }
        val unsigned = LicenseToken.unsigned(LicenseCrypto.keyId(pair.public), tagUid, userCode, issued, expires,
            ByteArray(4).also(random::nextBytes), if (remote) LicenseToken.FLAG_REMOTE else 0, LicenseRole.toBits(roles))
        return LicenseCrypto.sign(unsigned, pair.private, pair.public)
    }
}
