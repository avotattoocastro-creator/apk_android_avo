package org.avoperformance.horse.core.auth

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Application-level authorization of the phone (firmware V3.4.4, avo_ble_auth.cpp).
 *   watch_proof = HMAC-SHA256(K, "AVOW" | pn | wn | dev_id)
 *   phone_proof = HMAC-SHA256(K, "AVOP" | wn | pn | dev_id)
 * dev_id: the 12 hex chars reported by GET_INFO (zero padded to 12 bytes).
 */
object WatchAuth {
    private val rnd = SecureRandom()

    fun nonce(): ByteArray = ByteArray(16).also { rnd.nextBytes(it) }

    private fun proof(tag: String, key: ByteArray, a: ByteArray, b: ByteArray, devId: String): ByteArray {
        require(key.size == 32 && a.size == 16 && b.size == 16)
        val dev = ByteArray(12)
        val d = devId.toByteArray(Charsets.US_ASCII)
        System.arraycopy(d, 0, dev, 0, minOf(12, d.size))
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        mac.update(tag.toByteArray(Charsets.US_ASCII)); mac.update(a); mac.update(b); mac.update(dev)
        return mac.doFinal()
    }

    fun watchProof(key: ByteArray, phoneNonce: ByteArray, watchNonce: ByteArray, devId: String) = proof("AVOW", key, phoneNonce, watchNonce, devId)
    fun phoneProof(key: ByteArray, watchNonce: ByteArray, phoneNonce: ByteArray, devId: String) = proof("AVOP", key, watchNonce, phoneNonce, devId)

    /** Constant-time comparison. */
    fun same(a: ByteArray, b: ByteArray): Boolean = MessageDigest.isEqual(a, b)
}

/** Credential for one watch, as stored (encrypted) on the phone. */
data class WatchCredential(val deviceId: String, val keyId: ByteArray, val key: ByteArray) {
    init { require(keyId.size == 8 && key.size == 32) }
}
