package org.avoperformance.horse.identity

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.security.SecureStore

/**
 * Phone owner's AVO identity, taken from their NFC card. It is stored encrypted (SecureStore, Keystore)
 * and is not replaced by tapping another card: you have to "Olvidar" it first, so that a card
 * tapped by mistake (or someone else's) does not change the identity silently.
 */
class UserIdentity(private val secure: SecureStore) {
    private val _card = MutableStateFlow(load())
    val card: StateFlow<AvoUserCard?> = _card

    sealed interface Result {
        data class Adopted(val card: AvoUserCard) : Result
        data class Same(val card: AvoUserCard) : Result
        data class Other(val current: AvoUserCard, val tapped: AvoUserCard) : Result
    }

    fun onCardTapped(uri: String): Result {
        val tapped = AvoUserCard.parse(uri)
        val current = _card.value
        return when {
            current == null -> { save(tapped); Result.Adopted(tapped) }
            current.code == tapped.code -> { if (current != tapped) save(tapped); Result.Same(tapped) }
            else -> Result.Other(current, tapped)
        }
    }

    fun message(r: Result): String = when (r) {
        is Result.Adopted -> "Identidad AVO: ${r.card.name} (${r.card.code})"
        is Result.Same -> "Ya eres ${r.card.name} (${r.card.code})"
        is Result.Other -> "Tarjeta de ${r.tapped.name}: este móvil es de ${r.current.name}. Para cambiar, ve a NFC → Olvidar identidad."
    }

    fun forget() { secure.putString(KEY, null); _card.value = null }

    private fun save(c: AvoUserCard) { secure.putString(KEY, c.toUri()); _card.value = c }
    private fun load(): AvoUserCard? = secure.getString(KEY)?.let { runCatching { AvoUserCard.parse(it) }.getOrNull() }

    private companion object { const val KEY = "user.card.v1" }
}
