package org.avoperformance.cards

import android.content.Context
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.license.IssuerRegistry
import org.avoperformance.horse.core.license.RegEvent
import org.avoperformance.horse.core.license.RegUser
import org.avoperformance.horse.security.SecureStore

/**
 * Register of users and licences of AVO Tarjetas. It holds the card secrets, so it is stored encrypted with the
 * Android Keystore (SecureStore) and excluded from Android backups; the only portable copy is the password
 * backup (IssuerBackup). Replaces the old plain list "issued_cards" (migrated on first use, then wiped).
 */
class RegistryStore(ctx: Context) {
    private val secure = SecureStore(ctx)
    private val legacy = ctx.getSharedPreferences("issued_cards", Context.MODE_PRIVATE)

    @Synchronized
    fun load(): IssuerRegistry {
        val text = secure.getString(KEY)
        val reg = text?.let { runCatching { IssuerRegistry.decode(it) }.getOrNull() } ?: IssuerRegistry()
        return if (legacy.all.isEmpty()) reg else migrate(reg)
    }

    @Synchronized
    fun save(r: IssuerRegistry) = secure.putString(KEY, r.encode())

    /** Old format: "<cardUri>\t<createdMs>\t<revoked>[\t<expiresS>[\t<uidHex>[\t<rolesBits>]]]" per card. */
    private fun migrate(start: IssuerRegistry): IssuerRegistry {
        var r = start
        legacy.all.values.forEach { v ->
            val p = (v as? String)?.split('\t') ?: return@forEach
            if (p.size !in 3..6) return@forEach
            val card = runCatching { AvoUserCard.parse(p[0]) }.getOrNull() ?: return@forEach
            if (r.user(card.code) != null) return@forEach
            val created = p[1].toLongOrNull() ?: System.currentTimeMillis()
            r = r.upsert(RegUser(card, created, p[2] == "1", p.getOrNull(4).orEmpty(), p.getOrNull(5)?.toIntOrNull() ?: 0,
                p.getOrNull(3)?.toLongOrNull() ?: 0), RegEvent(created, card.code, RegEvent.Kind.ALTA, detail = "migrada de la lista anterior"))
        }
        save(r)
        legacy.edit().clear().apply()   // the secrets no longer stay in plain preferences
        return r
    }

    private companion object { const val KEY = "issuer.registry.v1" }
}
