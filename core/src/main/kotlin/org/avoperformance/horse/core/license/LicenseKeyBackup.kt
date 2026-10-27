package org.avoperformance.horse.core.license

import java.nio.ByteBuffer
import java.security.KeyPair
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Password-protected copy of the licence signing key (AVO Tarjetas → file kept by the owner).
 *
 * Text file: first line [HEADER], second line base64 of
 *   iterations(u32) | salt(16) | iv(12) | AES-256-GCM( len(u16) | SPKI | PKCS#8 )
 * The key is derived with PBKDF2-HMAC-SHA256. The header and the iteration count are authenticated
 * (GCM AAD), so the file cannot be altered without the password failing.
 */
object LicenseKeyBackup {
    const val HEADER = "AVO-LICENSE-KEY-BACKUP-1"
    const val MIN_PASSWORD = 10
    const val ITERATIONS = 310_000

    fun export(pair: KeyPair, password: CharArray, random: SecureRandom = SecureRandom(), iterations: Int = ITERATIONS): String {
        require(password.size >= MIN_PASSWORD) { "La contraseña debe tener al menos $MIN_PASSWORD caracteres" }
        val spki = pair.public.encoded
        val pkcs8 = pair.private.encoded
        val plain = ByteBuffer.allocate(2 + spki.size + pkcs8.size).putShort(spki.size.toShort()).put(spki).put(pkcs8).array()
        val salt = ByteArray(16).also(random::nextBytes)
        val iv = ByteArray(12).also(random::nextBytes)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, derive(password, salt, iterations), GCMParameterSpec(128, iv))
        c.updateAAD(aad(iterations))
        val ct = c.doFinal(plain)
        plain.fill(0)
        val blob = ByteBuffer.allocate(4 + 16 + 12 + ct.size).putInt(iterations).put(salt).put(iv).put(ct).array()
        return HEADER + "\n" + Base64.getMimeEncoder(76, "\n".toByteArray()).encodeToString(blob) + "\n"
    }

    /** Restores the key pair; wrong password or altered file → IllegalArgumentException. */
    fun import(text: String, password: CharArray): KeyPair {
        val lines = text.trim().lines()
        require(lines.firstOrNull()?.trim() == HEADER) { "No es una copia de la clave de licencias AVO" }
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
        val plain = try {
            Cipher.getInstance("AES/GCM/NoPadding").run {
                init(Cipher.DECRYPT_MODE, derive(password, salt, iterations), GCMParameterSpec(128, iv))
                updateAAD(aad(iterations)); doFinal(ct)
            }
        } catch (e: javax.crypto.AEADBadTagException) {
            throw IllegalArgumentException("Contraseña incorrecta o copia alterada")
        }
        val p = ByteBuffer.wrap(plain)
        val spkiLen = p.short.toInt() and 0xFFFF
        require(spkiLen in 1 until plain.size) { "Copia dañada" }
        val spki = ByteArray(spkiLen).also(p::get)
        val pkcs8 = ByteArray(p.remaining()).also(p::get)
        plain.fill(0)
        val pair = try { KeyPair(LicenseCrypto.publicKeyFromSpki(spki), LicenseCrypto.privateKeyFromPkcs8(pkcs8)) }
            catch (e: java.security.GeneralSecurityException) { throw IllegalArgumentException("Copia dañada") }
            finally { pkcs8.fill(0) }
        require(pairMatches(pair)) { "La clave privada no corresponde a la pública" }
        return pair
    }

    /** Signs and verifies a test message: proves the private key belongs to the public key. */
    fun pairMatches(pair: KeyPair): Boolean {
        val probe = LicenseToken.unsigned(LicenseCrypto.keyId(pair.public), byteArrayOf(1, 2, 3, 4, 5, 6, 7),
            "AVO-AAAA-AAAA", 1, 2, byteArrayOf(0, 0, 0, 0))
        return LicenseCrypto.verify(LicenseCrypto.sign(probe, pair.private, pair.public), pair.public)
    }

    private fun aad(iterations: Int) = (HEADER + ":" + iterations).toByteArray(Charsets.US_ASCII)

    private fun derive(password: CharArray, salt: ByteArray, iterations: Int): SecretKeySpec {
        val spec = PBEKeySpec(password, salt, iterations, 256)
        try {
            return SecretKeySpec(SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded, "AES")
        } finally { spec.clearPassword() }
    }
}
