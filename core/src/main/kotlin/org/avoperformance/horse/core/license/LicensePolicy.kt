package org.avoperformance.horse.core.license

import java.security.PublicKey
import java.util.Base64

/**
 * Time reference that cannot be moved back by changing the phone's clock.
 *
 *  - [highWaterMs]: highest trusted time ever seen; the effective time never goes below it.
 *  - [bootCount] + [wallMinusElapsedMs]: within the same Android boot, `elapsedRealtime` is monotonic
 *    and cannot be changed by the user, so `elapsed + offset` keeps counting even if the clock is
 *    moved back.
 *  - Network time (Android 13+, NTP/NITZ) is authoritative when available, and it also repairs a
 *    high-water mark that was pushed forward by a clock set in the future by mistake.
 */
data class ClockRecord(val highWaterMs: Long, val bootCount: Int, val wallMinusElapsedMs: Long)

data class ClockReading(val effectiveMs: Long, val record: ClockRecord, val systemClockBehind: Boolean, val source: String)

object LicenseClock {
    /** Tolerance before reporting that the phone clock is behind. */
    const val BEHIND_TOLERANCE_MS = 10 * 60_000L

    fun read(systemMs: Long, elapsedMs: Long, bootCount: Int, networkMs: Long?, previous: ClockRecord?): ClockReading {
        if (networkMs != null) {
            val rec = ClockRecord(networkMs, bootCount, networkMs - elapsedMs)
            return ClockReading(networkMs, rec, networkMs - systemMs > BEHIND_TOLERANCE_MS, "red")
        }
        var effective = systemMs
        var source = "móvil"
        if (previous != null) {
            if (previous.highWaterMs > effective) { effective = previous.highWaterMs; source = "última hora conocida" }
            if (bootCount >= 0 && previous.bootCount == bootCount) {
                val monotonic = elapsedMs + previous.wallMinusElapsedMs
                if (monotonic > effective) { effective = monotonic; source = "contador desde el arranque" }
            }
        }
        val offset = effective - elapsedMs
        val keepOffset = previous != null && previous.bootCount == bootCount && bootCount >= 0
        val rec = ClockRecord(effective, bootCount, if (keepOffset) maxOf(offset, previous!!.wallMinusElapsedMs) else offset)
        return ClockReading(effective, rec, effective - systemMs > BEHIND_TOLERANCE_MS, source)
    }
}

/** Licence accepted on this phone + its clock record. Stored as a single encrypted blob. */
data class StoredLicense(val token: LicenseToken, val clock: ClockRecord, val activatedAtMs: Long, val userName: String) {
    fun encode(): String = listOf("v1", b64(token.encode()), clock.highWaterMs, clock.bootCount, clock.wallMinusElapsedMs,
        activatedAtMs, b64(userName.toByteArray(Charsets.UTF_8))).joinToString("|")

    companion object {
        fun decode(s: String): StoredLicense {
            val p = s.split('|')
            require(p.size == 7 && p[0] == "v1") { "Registro de licencia no válido" }
            return StoredLicense(LicenseToken.decode(unb64(p[1])), ClockRecord(p[2].toLong(), p[3].toInt(), p[4].toLong()),
                p[5].toLong(), String(unb64(p[6]), Charsets.UTF_8))
        }
        private fun b64(b: ByteArray) = Base64.getEncoder().encodeToString(b)
        private fun unb64(s: String) = Base64.getDecoder().decode(s)
    }
}

sealed interface LicenseStatus {
    /** Build without trusted keys: licensing is not enforced (development builds). */
    data object NotEnforced : LicenseStatus
    data object None : LicenseStatus
    data class Active(val token: LicenseToken, val userName: String, val daysLeft: Long, val expiringSoon: Boolean) : LicenseStatus
    data class Expired(val token: LicenseToken, val userName: String) : LicenseStatus
    /** Stored licence no longer verifies (key removed from the app, damaged record…). */
    data class Invalid(val reason: String) : LicenseStatus

    /** Full use of the app (watch, NTRIP, tides, settings, sync). */
    val fullAccess: Boolean get() = this is NotEnforced || this is Active
}

sealed interface ActivationResult {
    data class Activated(val stored: StoredLicense, val renewed: Boolean) : ActivationResult
    data class AlreadyActive(val stored: StoredLicense) : ActivationResult
    data class Refused(val reason: String) : ActivationResult
}

/** Pure decisions (no Android): verification of a tapped card and status of the stored licence. */
object LicensePolicy {
    const val WARN_DAYS = 7L
    private const val DAY_MS = 86_400_000L

    /** Finds the trusted key matching the token's keyId and checks the signature. */
    fun verifySignature(token: LicenseToken, trusted: List<PublicKey>): Boolean =
        trusted.firstOrNull { LicenseCrypto.keyId(it).contentEquals(token.keyId) }?.let { LicenseCrypto.verify(token, it) } == true

    fun status(stored: StoredLicense?, trusted: List<PublicKey>, nowMs: Long): LicenseStatus {
        if (trusted.isEmpty()) return LicenseStatus.NotEnforced
        if (stored == null) return LicenseStatus.None
        if (!verifySignature(stored.token, trusted)) return LicenseStatus.Invalid("La licencia guardada no es válida para esta versión de la app")
        if (nowMs >= stored.token.expiresAtMs) return LicenseStatus.Expired(stored.token, stored.userName)
        val days = (stored.token.expiresAtMs - nowMs + DAY_MS - 1) / DAY_MS
        return LicenseStatus.Active(stored.token, stored.userName, days, days <= WARN_DAYS)
    }

    /**
     * Card tapped: [tokenBytes] from the NDEF licence record, [tagUid] from the NFC chip.
     * A card with a later expiry renews; an older one never replaces a licence that is still valid.
     */
    fun activate(
        tokenBytes: ByteArray?, tagUid: ByteArray?, userCode: String?, userName: String,
        trusted: List<PublicKey>, current: StoredLicense?, clock: ClockReading,
    ): ActivationResult {
        if (trusted.isEmpty()) return ActivationResult.Refused("Esta versión de la app no tiene licencias configuradas")
        if (tokenBytes == null) return ActivationResult.Refused("Esta tarjeta no lleva licencia de la app")
        val token = decodeOrNull(tokenBytes) ?: return ActivationResult.Refused("Licencia dañada")
        if (!verifySignature(token, trusted)) return ActivationResult.Refused("Licencia no válida: firma incorrecta o emitida por otra clave")
        if (tagUid == null || !tagUid.contentEquals(token.uid)) return ActivationResult.Refused("Licencia no válida: no pertenece a esta tarjeta (copia)")
        if (userCode != null && userCode != token.userCode) return ActivationResult.Refused("Licencia no válida: no corresponde al usuario de la tarjeta")
        return accept(token, userName, trusted, current, clock)
    }

    /**
     * Licence received as a file: [tokenBytes] already decrypted with the secret of the phone's identity card
     * ([identityCode]), which proves the file was made for this user. It must carry [LicenseToken.FLAG_REMOTE].
     */
    fun activateFromFile(
        tokenBytes: ByteArray, identityCode: String, userName: String,
        trusted: List<PublicKey>, current: StoredLicense?, clock: ClockReading,
    ): ActivationResult {
        if (trusted.isEmpty()) return ActivationResult.Refused("Esta versión de la app no tiene licencias configuradas")
        val token = decodeOrNull(tokenBytes) ?: return ActivationResult.Refused("Licencia dañada")
        if (!token.isRemote) return ActivationResult.Refused("Licencia no válida para activar por archivo")
        if (!verifySignature(token, trusted)) return ActivationResult.Refused("Licencia no válida: firma incorrecta o emitida por otra clave")
        if (token.userCode != identityCode) return ActivationResult.Refused("Licencia no válida: es de otro usuario")
        return accept(token, userName, trusted, current, clock)
    }

    private fun decodeOrNull(b: ByteArray) = try { LicenseToken.decode(b) } catch (e: IllegalArgumentException) { null }

    private fun accept(token: LicenseToken, userName: String, trusted: List<PublicKey>, current: StoredLicense?, clock: ClockReading): ActivationResult {
        if (clock.effectiveMs >= token.expiresAtMs) return ActivationResult.Refused("Esta licencia caducó")
        val now = clock.effectiveMs
        val fresh = StoredLicense(token, clock.record, now, userName)
        if (current == null || !verifySignature(current.token, trusted)) return ActivationResult.Activated(fresh, renewed = false)
        if (current.token == token) return ActivationResult.AlreadyActive(current.copy(clock = clock.record))
        val currentValid = now < current.token.expiresAtMs
        if (currentValid && token.expiresAtMs < current.token.expiresAtMs)
            return ActivationResult.Refused("Ya hay una licencia válida hasta una fecha posterior")
        return ActivationResult.Activated(fresh, renewed = true)
    }
}
