package org.avoperformance.horse.core.license

import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Password-protected text file for any content (used for the full AVO Tarjetas backup: signing key +
 * user register). Same scheme as [LicenseKeyBackup]:
 *
 *   <header>
 *   base64( iterations(u32) | salt(16) | iv(12) | AES-256-GCM(content) )
 *
 * Key derived with PBKDF2-HMAC-SHA256; header and iterations are authenticated (AAD).
 */
object PasswordBox {
    fun seal(header: String, content: ByteArray, password: CharArray, random: SecureRandom = SecureRandom(),
             iterations: Int = LicenseKeyBackup.ITERATIONS): String {
        require(password.size >= LicenseKeyBackup.MIN_PASSWORD) { "La contraseña debe tener al menos ${LicenseKeyBackup.MIN_PASSWORD} caracteres" }
        val salt = ByteArray(16).also(random::nextBytes)
        val iv = ByteArray(12).also(random::nextBytes)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, derive(password, salt, iterations), GCMParameterSpec(128, iv))
        c.updateAAD(aad(header, iterations))
        val ct = c.doFinal(content)
        val blob = ByteBuffer.allocate(4 + 16 + 12 + ct.size).putInt(iterations).put(salt).put(iv).put(ct).array()
        return header + "\n" + Base64.getMimeEncoder(76, "\n".toByteArray()).encodeToString(blob) + "\n"
    }

    fun isBox(text: String, header: String): Boolean = text.trimStart().lineSequence().firstOrNull()?.trim() == header

    /** Wrong password or altered file → IllegalArgumentException. */
    fun open(text: String, header: String, password: CharArray): ByteArray {
        val lines = text.trim().lines()
        require(lines.firstOrNull()?.trim() == header) { "No es un archivo de copia de AVO Tarjetas" }
        val blob = try { Base64.getMimeDecoder().decode(lines.drop(1).joinToString("")) } catch (e: IllegalArgumentException) {
            throw IllegalArgumentException("Copia dañada")
        }
        require(blob.size > 4 + 16 + 12 + 16) { "Copia dañada" }
        val b = ByteBuffer.wrap(blob)
        val iterations = b.int
        require(iterations in 100_000..5_000_000) { "Copia dañada" }
        val salt = ByteArray(16).also(b::get)
        val iv = ByteArray(12).also(b::get)
        val ct = ByteArray(b.remaining()).also(b::get)
        return try {
            Cipher.getInstance("AES/GCM/NoPadding").run {
                init(Cipher.DECRYPT_MODE, derive(password, salt, iterations), GCMParameterSpec(128, iv))
                updateAAD(aad(header, iterations)); doFinal(ct)
            }
        } catch (e: javax.crypto.AEADBadTagException) {
            throw IllegalArgumentException("Contraseña incorrecta o copia alterada")
        }
    }

    private fun aad(header: String, iterations: Int) = "$header:$iterations".toByteArray(Charsets.UTF_8)

    private fun derive(password: CharArray, salt: ByteArray, iterations: Int): SecretKeySpec {
        val spec = PBEKeySpec(password, salt, iterations, 256)
        try {
            return SecretKeySpec(SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded, "AES")
        } finally { spec.clearPassword() }
    }
}
