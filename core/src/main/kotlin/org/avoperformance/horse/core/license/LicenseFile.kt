package org.avoperformance.horse.core.license

import org.avoperformance.horse.core.identity.AvoUserCard
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Licence sent as a file (email, WhatsApp) to a user who cannot bring the card.
 *
 *   AVO-LICENSE-FILE-1
 *   <user code>
 *   <base64( iv(12) | AES-256-GCM(signed licence token) )>
 *
 * The AES key is derived from the secret of the user's card (`k`, 128 bit, only on the card, on the
 * issuer's phone and on phones where that card was tapped): a forwarded file cannot be opened on a
 * phone that never read that card. The token inside is signed (ECDSA) with the [LicenseToken.FLAG_REMOTE]
 * flag, so the date cannot be changed either.
 */
object LicenseFile {
    const val HEADER = "AVO-LICENSE-FILE-1"
    const val EXTENSION = "avolic"

    fun looksLikeLicenseFile(start: ByteArray): Boolean =
        String(start.copyOf(minOf(start.size, HEADER.length)), Charsets.US_ASCII) == HEADER

    fun encode(token: LicenseToken, card: AvoUserCard, random: SecureRandom = SecureRandom()): String {
        require(token.isRemote) { "La licencia no está marcada para envío por archivo" }
        require(token.userCode == card.code) { "La licencia no es de este usuario" }
        val iv = ByteArray(12).also(random::nextBytes)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key(card.secret), GCMParameterSpec(128, iv))
        c.updateAAD(aad(card.code))
        val blob = iv + c.doFinal(token.encode())
        return "$HEADER\n${card.code}\n${Base64.getEncoder().encodeToString(blob)}\n"
    }

    /** User code written in clear in the file (to tell the user whose file it is). */
    fun userCodeOf(text: String): String? = text.trim().lines().takeIf { it.firstOrNull()?.trim() == HEADER }?.getOrNull(1)?.trim()

    /** Decrypts the token with the secret of [card]; IllegalArgumentException if it is not this user's file. */
    fun decode(text: String, card: AvoUserCard): ByteArray {
        val lines = text.trim().lines().map { it.trim() }
        require(lines.size >= 3 && lines[0] == HEADER) { "No es un archivo de licencia AVO" }
        require(lines[1] == card.code) { "Este archivo es para el usuario ${lines[1]}, no para ${card.code}" }
        val blob = try { Base64.getDecoder().decode(lines.drop(2).joinToString("")) } catch (e: IllegalArgumentException) {
            throw IllegalArgumentException("Archivo de licencia dañado")
        }
        require(blob.size > 12 + 16) { "Archivo de licencia dañado" }
        return try {
            Cipher.getInstance("AES/GCM/NoPadding").run {
                init(Cipher.DECRYPT_MODE, key(card.secret), GCMParameterSpec(128, blob, 0, 12))
                updateAAD(aad(card.code)); doFinal(blob, 12, blob.size - 12)
            }
        } catch (e: javax.crypto.AEADBadTagException) {
            throw IllegalArgumentException("El archivo no corresponde a la tarjeta de este móvil o está alterado")
        }
    }

    private fun aad(code: String) = "$HEADER:$code".toByteArray(Charsets.US_ASCII)

    private fun key(secretHex: String): SecretKeySpec {
        val secret = ByteArray(secretHex.length / 2) { secretHex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(secret, "HmacSHA256")) }
        secret.fill(0)
        return SecretKeySpec(mac.doFinal("AVO-LICENSE-FILE/1".toByteArray(Charsets.US_ASCII)), "AES")
    }
}
