package org.avoperformance.horse.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.avoperformance.horse.core.auth.WatchCredential
import org.avoperformance.horse.core.bytes.hexToBytes
import org.avoperformance.horse.core.bytes.toHex
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Secrets (watch keys, NTRIP password, future server token) encrypted with an
 * AES-256-GCM key that lives in the Android Keystore and never leaves it.
 * Nothing secret is in the source code or in plain SharedPreferences.
 */
class SecureStore(ctx: Context) {
    private val prefs = ctx.getSharedPreferences("avo_secure", Context.MODE_PRIVATE)
    private val alias = "avo_secure_store_v1"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        g.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return g.generateKey()
    }

    @Synchronized
    fun put(name: String, value: ByteArray?) {
        if (value == null) { prefs.edit().remove(name).apply(); return }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        c.updateAAD(name.toByteArray())
        val ct = c.doFinal(value)
        val blob = c.iv + ct
        prefs.edit().putString(name, Base64.encodeToString(blob, Base64.NO_WRAP)).apply()
    }

    @Synchronized
    fun get(name: String): ByteArray? {
        val s = prefs.getString(name, null) ?: return null
        return try {
            val blob = Base64.decode(s, Base64.NO_WRAP)
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, blob, 0, 12))
            c.updateAAD(name.toByteArray())
            c.doFinal(blob, 12, blob.size - 12)
        } catch (e: Exception) {
            null   // key invalidated (e.g. device restore): the user must pair again
        }
    }

    fun putString(name: String, v: String?) = put(name, v?.toByteArray(Charsets.UTF_8))
    fun getString(name: String): String? = get(name)?.toString(Charsets.UTF_8)

    // ---- watch credentials (one per watch, key = BLE address)
    fun saveWatch(address: String, cred: WatchCredential) =
        putString("watch:$address", "${cred.deviceId}|${cred.keyId.toHex()}|${cred.key.toHex()}")

    fun watch(address: String): WatchCredential? = getString("watch:$address")?.split('|')?.takeIf { it.size == 3 }?.let {
        WatchCredential(it[0], it[1].hexToBytes(), it[2].hexToBytes())
    }

    fun forgetWatch(address: String) = put("watch:$address", null)

    var ntripPassword: String?
        get() = getString("ntrip:password")
        set(v) = putString("ntrip:password", v)
}
