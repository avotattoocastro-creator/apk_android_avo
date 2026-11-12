package org.avoperformance.cards

import android.net.Uri
import android.nfc.FormatException
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.license.LicenseToken

/**
 * Reads/writes the NDEF message of a user card:
 *   1. URI record (identity), 2. optional licence record (external type `avoperformance.org:lic`),
 *   3. AAR (opens AVO Performance Horse on tap).
 */
object CardWriter {
    const val MAIN_APP = "org.avoperformance.horse"

    fun message(card: AvoUserCard, license: ByteArray? = null) = NdefMessage(buildList {
        add(NdefRecord.createUri(Uri.parse(card.toUri())))
        if (license != null) add(NdefRecord.createExternal(LicenseToken.NDEF_DOMAIN, LicenseToken.NDEF_TYPE, license))
        add(NdefRecord.createApplicationRecord(MAIN_APP))
    }.toTypedArray())

    /** Licence bytes inside an NDEF message, or null. */
    fun licenseOf(msg: NdefMessage?): ByteArray? = msg?.records?.firstOrNull {
        it.tnf == NdefRecord.TNF_EXTERNAL_TYPE && String(it.type, Charsets.US_ASCII).lowercase() == LicenseToken.NDEF_EXTERNAL_TYPE
    }?.payload

    data class Read(val uri: String?, val license: ByteArray?)

    /** Identity URI and licence of the card (null fields if empty / not NDEF). */
    fun read(tag: Tag): Read {
        val ndef = Ndef.get(tag) ?: return Read(null, null)
        ndef.connect()
        return try {
            val msg = ndef.ndefMessage
            Read(msg?.records?.firstNotNullOfOrNull { it.toUri()?.toString() }, licenseOf(msg))
        } catch (_: FormatException) { Read(null, null) } finally { ndef.close() }
    }

    sealed interface Outcome {
        data class Written(val verified: Boolean, val locked: Boolean) : Outcome
        data class Refused(val reason: String) : Outcome
    }

    /**
     * Writes [card] and, when [licenseFor] is given, the licence signed for THIS card's UID (the UID is
     * only known once the card is in the field). Refuses: cards protected against writing, cards that are
     * too small, and a card that already has ANOTHER user's identity or a horse/rider tag, unless
     * [overwrite] is true. [lock] makes the card read-only: IRREVERSIBLE (and a licence could never be renewed).
     */
    fun write(tag: Tag, card: AvoUserCard, overwrite: Boolean, lock: Boolean, licenseFor: ((ByteArray) -> ByteArray)? = null): Outcome {
        val license = licenseFor?.invoke(tag.id ?: return Outcome.Refused("La tarjeta no tiene UID legible"))
        val msg = message(card, license)
        val ndef = Ndef.get(tag)
        if (ndef == null) {
            val f = NdefFormatable.get(tag) ?: return Outcome.Refused("La tarjeta no admite NDEF (usa NTAG213/215/216)")
            f.connect()
            try { if (lock) f.formatReadOnly(msg) else f.format(msg) } finally { f.close() }
            return Outcome.Written(verified = false, locked = lock) // Android does not let you re-read it until the card is moved away
        }
        ndef.connect()
        try {
            if (!ndef.isWritable) return Outcome.Refused("Tarjeta bloqueada (solo lectura)")
            if (ndef.maxSize < msg.byteArrayLength) return Outcome.Refused("Tarjeta pequeña: ${ndef.maxSize} B, hacen falta ${msg.byteArrayLength} B (usa NTAG215/216 o un nombre más corto)")
            val existing = runCatching { ndef.ndefMessage?.records?.firstNotNullOfOrNull { it.toUri()?.toString() } }.getOrNull()
            if (!overwrite && existing != null && existing.startsWith("avohorse://")) {
                val same = AvoUserCard.isUserUri(existing) && runCatching { AvoUserCard.parse(existing).code }.getOrNull() == card.code
                if (!same) return Outcome.Refused("La tarjeta ya tiene datos AVO (${describe(existing)}). Marca «Sobrescribir» si quieres reutilizarla.")
            }
            ndef.writeNdefMessage(msg)
            val back = ndef.ndefMessage
            val verified = back?.records?.firstNotNullOfOrNull { it.toUri()?.toString() } == card.toUri() &&
                (license == null || licenseOf(back)?.contentEquals(license) == true)
            val locked = lock && verified && ndef.canMakeReadOnly() && ndef.makeReadOnly()
            return Outcome.Written(verified, locked)
        } finally { ndef.close() }
    }

    fun describe(uri: String): String = when {
        AvoUserCard.isUserUri(uri) -> runCatching { AvoUserCard.parse(uri).let { "usuario ${it.name} · ${it.code}" } }.getOrDefault("usuario (dañada)")
        uri.startsWith("avohorse://identity/horse/") -> "caballo"
        uri.startsWith("avohorse://identity/rider/") -> "jinete"
        else -> uri.take(40)
    }
}
