package org.avoperformance.horse.core.license

import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * ECDSA P-256 / SHA-256 for AVO licences. Only the issuer (AVO Tarjetas) holds the private key;
 * the main app is built with the public key(s) and can only verify.
 */
object LicenseCrypto {
    /** Order n of the P-256 curve: used to check that a public key really is P-256. */
    private val P256_N = BigInteger("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", 16)

    fun generateKeyPair(random: SecureRandom = SecureRandom()): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1"), random) }.generateKeyPair()

    /** First 4 bytes of SHA-256(SubjectPublicKeyInfo). */
    fun keyId(publicKey: PublicKey): ByteArray = MessageDigest.getInstance("SHA-256").digest(publicKey.encoded).copyOf(4)

    fun publicKeyFromSpki(spki: ByteArray): PublicKey {
        val k = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(spki))
        require(k is ECPublicKey && k.params.order == P256_N) { "La clave pública no es ECDSA P-256" }
        return k
    }

    fun privateKeyFromPkcs8(pkcs8: ByteArray): PrivateKey = KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(pkcs8))

    fun publicKeyToBase64(k: PublicKey): String = Base64.getEncoder().encodeToString(k.encoded)

    /**
     * Trusted keys compiled into the app: base64 SPKI separated by commas, spaces or new lines.
     * Invalid entries make the whole list invalid (a typo must not silently disable a key).
     */
    fun parseTrustedKeys(text: String?): List<PublicKey> = text.orEmpty()
        .split(',', ' ', '\n', '\r', '\t', ';').map { it.trim() }.filter { it.isNotEmpty() }
        .map { publicKeyFromSpki(Base64.getDecoder().decode(it)) }

    /** Signs [unsigned] and returns the complete token. The keyId inside must match [publicKey]. */
    fun sign(unsigned: LicenseToken, privateKey: PrivateKey, publicKey: PublicKey): LicenseToken {
        require(unsigned.keyId.contentEquals(keyId(publicKey))) { "keyId no coincide con la clave" }
        val der = Signature.getInstance("SHA256withECDSA").run { initSign(privateKey); update(unsigned.signedBytes()); sign() }
        return unsigned.withSignature(derToRaw(der))
    }

    fun verify(token: LicenseToken, publicKey: PublicKey): Boolean = try {
        Signature.getInstance("SHA256withECDSA").run { initVerify(publicKey); update(token.signedBytes()); verify(rawToDer(token.signature)) }
    } catch (_: Exception) { false }

    // ---- ECDSA signature encoding: raw r||s (32+32) <-> ASN.1 DER SEQUENCE { INTEGER r, INTEGER s }

    fun derToRaw(der: ByteArray): ByteArray {
        var i = 0
        require(der[i++] == 0x30.toByte()) { "DER" }
        var len = der[i++].toInt() and 0xFF
        if (len and 0x80 != 0) { val n = len and 0x7F; len = 0; repeat(n) { len = (len shl 8) or (der[i++].toInt() and 0xFF) } }
        fun int(): ByteArray {
            require(der[i++] == 0x02.toByte()) { "DER" }
            val l = der[i++].toInt() and 0xFF
            val v = der.copyOfRange(i, i + l); i += l
            val stripped = v.dropWhile { it == 0.toByte() }.toByteArray()
            require(stripped.size <= 32) { "DER" }
            return ByteArray(32 - stripped.size) + stripped
        }
        return int() + int()
    }

    fun rawToDer(raw: ByteArray): ByteArray {
        require(raw.size == 64) { "firma" }
        fun int(b: ByteArray): ByteArray {
            var v = b.dropWhile { it == 0.toByte() }.toByteArray()
            if (v.isEmpty()) v = byteArrayOf(0)
            if (v[0].toInt() and 0x80 != 0) v = byteArrayOf(0) + v
            return byteArrayOf(0x02, v.size.toByte()) + v
        }
        val body = int(raw.copyOfRange(0, 32)) + int(raw.copyOfRange(32, 64))
        return byteArrayOf(0x30, body.size.toByte()) + body
    }
}
