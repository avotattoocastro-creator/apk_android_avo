package org.avoperformance.horse.core.identity

import java.net.URLDecoder
import java.net.URLEncoder
import java.security.SecureRandom

/**
 * AVO user card (NFC): unique code + name + secret key. It identifies a person for app-to-app sending,
 * and it moves with the card when the phone changes. Format in the tag: one NDEF URI record
 *
 *   avohorse://identity/user/AVO-XXXX-XXXX?v=1&name=<name>&k=<32 hex>
 *
 * Same scheme/host as the horse/rider tags (`identity/horse|rider`); older versions of the app ignore it.
 * The secret `k` is only for signing in to the transfer service; it must never be shown or logged.
 * Simple card (NTAG213/215/216): it can be copied if someone has it in hand; it is designed for home use.
 */
data class AvoUserCard(val code: String, val name: String, val secret: String) {
    init {
        require(CODE.matches(code)) { "Código de tarjeta no válido" }
        require(name.isNotBlank() && name.length <= MAX_NAME && name.none { it.isISOControl() }) { "Nombre no válido" }
        require(SECRET.matches(secret)) { "Clave de tarjeta no válida" }
    }

    fun toUri(): String = "avohorse://identity/user/$code?v=1&name=${enc(name)}&k=$secret"

    /** Version without the secret, safe to show or log. */
    override fun toString(): String = "AvoUserCard($code, $name)"

    companion object {
        private const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789" // no 0/O/1/I/L to avoid misreading
        val CODE = Regex("AVO-[$ALPHABET]{4}-[$ALPHABET]{4}")
        val SECRET = Regex("[0-9a-f]{32}")
        const val MAX_NAME = 40
        private const val PREFIX = "avohorse://identity/user/"

        fun isUserUri(uri: String?): Boolean = uri?.startsWith(PREFIX) == true

        fun parse(uri: String): AvoUserCard {
            require(isUserUri(uri)) { "No es una tarjeta de usuario AVO" }
            val rest = uri.removePrefix(PREFIX)
            val code = rest.substringBefore('?')
            val query = rest.substringAfter('?', "").split('&').filter { it.isNotEmpty() }.associate {
                URLDecoder.decode(it.substringBefore('='), "UTF-8") to URLDecoder.decode(it.substringAfter('=', ""), "UTF-8")
            }
            require(query["v"] == "1") { "Versión de tarjeta no compatible" }
            return AvoUserCard(code, query["name"].orEmpty().trim(), query["k"].orEmpty())
        }

        fun generate(name: String, random: SecureRandom = SecureRandom()): AvoUserCard {
            fun block() = (1..4).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")
            val secret = ByteArray(16).also(random::nextBytes).joinToString("") { "%02x".format(it) }
            return AvoUserCard("AVO-${block()}-${block()}", name.trim(), secret)
        }

        private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
    }
}
