package org.avoperformance.cards

import android.content.Context
import org.avoperformance.horse.core.license.LicenseCrypto
import org.avoperformance.horse.core.license.LicenseKeyBackup
import org.avoperformance.horse.security.SecureStore
import java.nio.ByteBuffer
import java.security.KeyPair

/**
 * Licence signing key of this phone. Encrypted at rest with an AES-256-GCM key that lives in the Android
 * Keystore (SecureStore) and excluded from Android backups (allowBackup=false). The only way to move it
 * to another phone is the password-protected copy ([LicenseKeyBackup]) that the owner keeps.
 */
class LicenseKeyStore(ctx: Context) {
    private val secure = SecureStore(ctx)

    fun load(): KeyPair? = secure.get(KEY)?.let { blob ->
        runCatching {
            val b = ByteBuffer.wrap(blob)
            val spki = ByteArray(b.short.toInt() and 0xFFFF).also(b::get)
            val pkcs8 = ByteArray(b.remaining()).also(b::get)
            KeyPair(LicenseCrypto.publicKeyFromSpki(spki), LicenseCrypto.privateKeyFromPkcs8(pkcs8))
        }.getOrNull()
    }

    fun save(pair: KeyPair) {
        require(LicenseKeyBackup.pairMatches(pair)) { "Par de claves no válido" }
        val spki = pair.public.encoded
        val pkcs8 = pair.private.encoded
        val blob = ByteBuffer.allocate(2 + spki.size + pkcs8.size).putShort(spki.size.toShort()).put(spki).put(pkcs8).array()
        secure.put(KEY, blob)
        blob.fill(0); pkcs8.fill(0)
    }

    fun generate(): KeyPair = LicenseCrypto.generateKeyPair().also(::save)

    private companion object { const val KEY = "license.signing.key.v1" }
}
