package org.avoperformance.cards

import android.net.Uri
import android.nfc.FormatException
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import org.avoperformance.horse.core.identity.AvoUserCard

/** Reads/writes the NDEF message of a user card: URI record + AAR (opens AVO Performance Horse on tap). */
object CardWriter {
    const val MAIN_APP = "org.avoperformance.horse"

    fun message(card: AvoUserCard) = NdefMessage(arrayOf(
        NdefRecord.createUri(Uri.parse(card.toUri())),
        NdefRecord.createApplicationRecord(MAIN_APP),
    ))

    /** Text of the first URI record on the card, or null if it is empty / not NDEF. */
    fun readUri(tag: Tag): String? {
        val ndef = Ndef.get(tag) ?: return null
        ndef.connect()
        return try { ndef.ndefMessage?.records?.firstNotNullOfOrNull { it.toUri()?.toString() } }
        catch (_: FormatException) { null } finally { ndef.close() }
    }

    sealed interface Outcome {
        data class Written(val verified: Boolean, val locked: Boolean) : Outcome
        data class Refused(val reason: String) : Outcome
    }

    /**
     * Writes [card]. It refuses: cards protected against writing, cards that are too small, and a card
     * that already has ANOTHER user's identity or a horse/rider tag, unless [overwrite] is true.
     * [lock] makes the card read-only: IRREVERSIBLE.
     */
    fun write(tag: Tag, card: AvoUserCard, overwrite: Boolean, lock: Boolean): Outcome {
        val msg = message(card)
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
            val verified = ndef.ndefMessage?.records?.firstNotNullOfOrNull { it.toUri()?.toString() } == card.toUri()
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
