package org.avoperformance.signer

import android.content.Context
import org.json.JSONObject
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/** Portable encrypted EC P-256 signing identity. No unencrypted private key on disk. */
class SecureKeyVault(private val context: Context) {
    private val filename = "avo_signer_recoverable_key.json"
    private val random = SecureRandom()
    private val iterations = 600_000
    private fun b64(bytes:ByteArray)=Base64.getEncoder().encodeToString(bytes)
    private fun un64(text:String)=Base64.getDecoder().decode(text)
    fun exists()=context.getFileStreamPath(filename).exists()
    fun encryptedBackup():ByteArray = context.openFileInput(filename).use { it.readBytes() }
    fun publicKey():PublicKey {
        val j=JSONObject(String(encryptedBackup(),Charsets.UTF_8))
        return KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(un64(j.getString("public_spki"))))
    }
    fun generate(password:CharArray):ByteArray {
        require(!exists()) { "Ya existe una clave recuperable. No se reemplaza." }
        val gen=KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec("secp256r1"),random)
        val pair=gen.generateKeyPair()
        val backup=encrypt(pair,password)
        importBackup(backup,password)
        return backup
    }
    private fun derive(password:CharArray,salt:ByteArray,rounds:Int):SecretKeySpec {
        val spec=PBEKeySpec(password,salt,rounds,256)
        return try {
            val bytes=SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
            try { SecretKeySpec(bytes,"AES") } finally { bytes.fill(0) }
        } finally { spec.clearPassword() }
    }
    private fun encrypt(pair:KeyPair,password:CharArray):ByteArray {
        require(password.size>=14) { "Contraseña: mínimo 14 caracteres" }
        val salt=ByteArray(16).also { random.nextBytes(it) }
        val nonce=ByteArray(12).also { random.nextBytes(it) }
        val key=derive(password,salt,iterations)
        val cipher=Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE,key,GCMParameterSpec(128,nonce))
        val pub=pair.public.encoded
        cipher.updateAAD(pub)
        val encrypted=cipher.doFinal(pair.private.encoded)
        return JSONObject()
            .put("format","avo-encrypted-key-v1")
            .put("alg","ES256").put("kid","AVO_OTA_RECOVERABLE_P256_V1")
            .put("kdf","PBKDF2-HMAC-SHA256").put("iterations",iterations)
            .put("cipher","AES-256-GCM")
            .put("salt",b64(salt)).put("nonce",b64(nonce))
            .put("public_spki",b64(pub)).put("encrypted_pkcs8",b64(encrypted))
            .toString(2).toByteArray(Charsets.UTF_8)
    }
    private fun decode(bytes:ByteArray,password:CharArray):KeyPair {
        require(bytes.size in 100..16384) { "Archivo de clave inválido" }
        val j=JSONObject(String(bytes,Charsets.UTF_8))
        require(j.getString("format")=="avo-encrypted-key-v1")
        require(j.getString("alg")=="ES256" && j.getString("cipher")=="AES-256-GCM")
        require(j.getString("kdf")=="PBKDF2-HMAC-SHA256")
        val rounds=j.getInt("iterations")
        require(rounds in 600_000..2_000_000) { "Parámetros KDF no admitidos" }
        val salt=un64(j.getString("salt")); val nonce=un64(j.getString("nonce"))
        require(salt.size==16 && nonce.size==12)
        val pub=un64(j.getString("public_spki"))
        val encrypted=un64(j.getString("encrypted_pkcs8"))
        val cipher=Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE,derive(password,salt,rounds),GCMParameterSpec(128,nonce))
        cipher.updateAAD(pub)
        val plain=cipher.doFinal(encrypted)
        val factory=KeyFactory.getInstance("EC")
        val pair=try {
            KeyPair(factory.generatePublic(X509EncodedKeySpec(pub)),factory.generatePrivate(PKCS8EncodedKeySpec(plain)))
        } finally { plain.fill(0) }
        // Prove that the private key matches the included public key.
        val challenge=ByteArray(32).also { random.nextBytes(it) }
        val signer=java.security.Signature.getInstance("SHA256withECDSA")
        signer.initSign(pair.private); signer.update(challenge)
        val signature=signer.sign()
        val verifier=java.security.Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(pair.public); verifier.update(challenge)
        require(verifier.verify(signature)) { "La clave privada no corresponde a la pública" }
        return pair
    }
    fun importBackup(bytes:ByteArray,password:CharArray) {
        require(!exists()) { "Ya hay una clave recuperable. No se sobrescribe." }
        decode(bytes,password)
        context.openFileOutput(filename,Context.MODE_PRIVATE).use { it.write(bytes) }
    }
    fun unlock(password:CharArray):KeyPair=decode(encryptedBackup(),password)
    fun publicJson():String=JSONObject().put("format","avo-public-key-v1")
        .put("alg","ES256").put("kid","AVO_OTA_RECOVERABLE_P256_V1")
        .put("spki_der_base64",b64(publicKey().encoded)).toString(2)
}
