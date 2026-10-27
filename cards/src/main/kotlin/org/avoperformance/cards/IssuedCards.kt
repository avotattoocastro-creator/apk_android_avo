package org.avoperformance.cards

import android.content.Context
import org.avoperformance.horse.core.identity.AvoUserCard

/**
 * Issued card on this device. `revoked` = withdrawn (lost card); it takes effect once the transfer service exists.
 * [licenseExpiresS]: expiry of the last licence given to this user from this phone (card or file; 0 = none).
 * [uidHex]: UID of the chip the last licence was written to ("" = unknown).
 */
data class Issued(val card: AvoUserCard, val createdMs: Long, val revoked: Boolean, val licenseExpiresS: Long = 0, val uidHex: String = "")

/**
 * Register of issued cards (app private storage, no backup). It keeps the secret so a card can be
 * re-written (copy) if it breaks. Home use: if this phone is lost, the cards stay valid until revoked.
 */
class IssuedCards(ctx: Context) {
    private val p = ctx.getSharedPreferences("issued_cards", Context.MODE_PRIVATE)

    fun all(): List<Issued> = p.all.values.mapNotNull { v ->
        val parts = (v as? String)?.split('\t') ?: return@mapNotNull null
        if (parts.size !in 3..5) return@mapNotNull null
        runCatching { Issued(AvoUserCard.parse(parts[0]), parts[1].toLong(), parts[2] == "1", parts.getOrNull(3)?.toLong() ?: 0, parts.getOrNull(4).orEmpty()) }.getOrNull()
    }.sortedByDescending { it.createdMs }

    fun save(i: Issued) {
        p.edit().putString(i.card.code, "${i.card.toUri()}\t${i.createdMs}\t${if (i.revoked) 1 else 0}\t${i.licenseExpiresS}\t${i.uidHex}").apply()
    }
    fun byCode(code: String): Issued? = all().firstOrNull { it.card.code == code }
}
