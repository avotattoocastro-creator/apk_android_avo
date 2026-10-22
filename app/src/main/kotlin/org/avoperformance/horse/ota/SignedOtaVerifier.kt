package org.avoperformance.horse.ota

import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.util.zip.ZipInputStream

/**
 * Offline AVO OTA package verifier. Never trust public keys carried by the ZIP.
 * Does not authorize flashing by itself: the chest must independently enforce signatures.
 */
object SignedOtaVerifier {
    private const val MAX_ZIP_BYTES = 5 * 1024 * 1024
    private const val MAX_BIN_BYTES = 4 * 1024 * 1024
    private const val TARGET = "AVO_CHEST_WAVESHARE_ESP32S3"
    private val trustedSpki = mapOf(
        "AVO_OTA_RECOVERABLE_P256_V1" to "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEKIADU/bALRoURAxF4ElSbDZkbDRxDxl8cP6YIm0xsmWG3fallhy29ynUhh/oZAOiasc7DAucXj7FrUr8LskriA=="
    )
    data class Verified(val firmware: ByteArray, val version: String, val keyId: String)
    fun verify(zip: ByteArray): Verified {
        require(zip.size in 1..MAX_ZIP_BYTES) { "Tamaño ZIP inválido" }
        val members = mutableMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(zip)).use { stream ->
            while (true) {
                val entry = stream.nextEntry ?: break
                require(!entry.isDirectory && entry.name in setOf("firmware.bin", "manifest.json", "manifest.sig")) { "Entrada OTA inesperada" }
                require(!members.containsKey(entry.name)) { "Entrada OTA duplicada" }
                val max = if (entry.name == "firmware.bin") MAX_BIN_BYTES else 64 * 1024
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(8192)
                while (true) {
                    val count = stream.read(buf)
                    if (count < 0) break
                    require(out.size() + count <= max) { "Entrada OTA demasiado grande" }
                    out.write(buf, 0, count)
                }
                members[entry.name] = out.toByteArray()
                stream.closeEntry()
            }
        }
        require(members.keys == setOf("firmware.bin", "manifest.json", "manifest.sig")) { "Paquete OTA incompleto" }
        val manifestBytes = members.getValue("manifest.json")
        val manifest = JSONObject(manifestBytes.toString(Charsets.UTF_8))
        require(manifest.getString("schema") == "avo-ota-manifest-v1") { "Esquema OTA desconocido" }
        require(manifest.getString("alg") == "ES256") { "Algoritmo OTA no admitido" }
        require(manifest.getString("target") == TARGET) { "Firmware para otro dispositivo" }
        require(manifest.getString("firmware") == "firmware.bin") { "Nombre de firmware inválido" }
        val kid = manifest.getString("kid")
        val keyB64 = trustedSpki[kid] ?: error("Clave OTA no autorizada")
        val firmware = members.getValue("firmware.bin")
        require(firmware.isNotEmpty() && firmware.size == manifest.getInt("size")) { "Longitud de firmware incorrecta" }
        val digest = MessageDigest.getInstance("SHA-256").digest(firmware)
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        require(MessageDigest.isEqual(digest.toByteArray(Charsets.US_ASCII),
            manifest.getString("sha256").lowercase().toByteArray(Charsets.US_ASCII))) { "SHA-256 incorrecto" }
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(keyB64)))
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initVerify(key)
        signature.update(manifestBytes)
        require(signature.verify(members.getValue("manifest.sig"))) { "Firma OTA inválida" }
        val version = manifest.getString("version")
        require(Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(version)) { "Versión OTA inválida" }
        return Verified(firmware, version, kid)
    }
}
