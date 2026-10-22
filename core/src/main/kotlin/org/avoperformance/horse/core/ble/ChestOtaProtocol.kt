package org.avoperformance.horse.core.ble

import org.avoperformance.horse.core.bytes.ByteWriter
import java.security.MessageDigest

/** Verified against V3.5.0 src/ble_service.cpp and src/ota.cpp (20 Oct 2026).
 * No digital signature verification is implemented in that firmware; SHA-256
 * verifies transport integrity, NOT manufacturer authenticity. */
object ChestOtaProtocol {
    const val IMAGE_MARKER = "AVOCHEST-IMG-V1:WS-AMOLED-2.06"
    const val MAX_FILE_SIZE = 8 * 1024 * 1024
    const val ESP_MAGIC = 0xE9
    const val MAX_DATA_CHUNK = 1024

    data class Inspection(val valid: Boolean, val reason: String, val sha256: ByteArray, val size: Int)

    fun inspect(image: ByteArray): Inspection {
        val sha = MessageDigest.getInstance("SHA-256").digest(image)
        if (image.size < 288 || image.size > MAX_FILE_SIZE) return Inspection(false, "Tamaño no válido para un firmware ESP32-S3", sha, image.size)
        if ((image[0].toInt() and 0xFF) != ESP_MAGIC) return Inspection(false, "No es una imagen de aplicación ESP32", sha, image.size)
        val marker = IMAGE_MARKER.toByteArray(Charsets.US_ASCII)
        if (!contains(image, marker)) return Inspection(false, "Falta la identificación AVO del firmware de pecho", sha, image.size)
        return Inspection(true, "Imagen ESP y marca de pecho reconocidas; autenticidad NO verificada", sha, image.size)
    }

    private fun contains(data: ByteArray, needle: ByteArray): Boolean {
        outer@ for (i in 0..(data.size - needle.size)) {
            for (j in needle.indices) if (data[i + j] != needle[j]) continue@outer
            return true
        }
        return false
    }

    fun authPayload(manifest: ByteArray, signature: ByteArray): ByteArray {
        require(manifest.size in 30..2048)
        require(signature.size in 64..80)
        return ByteWriter(4 + manifest.size + signature.size)
            .u16(manifest.size).u16(signature.size).bytes(manifest).bytes(signature).toByteArray()
    }
    fun beginPayload(image: ByteArray): ByteArray {
        val check = inspect(image)
        require(check.valid) { check.reason }
        return ByteWriter(36).u32(image.size.toLong()).bytes(check.sha256).toByteArray()
    }

    fun dataPayload(offset: Int, image: ByteArray, size: Int): ByteArray {
        require(offset >= 0 && size in 1..MAX_DATA_CHUNK && offset + size <= image.size)
        return ByteWriter(4 + size).u32(offset.toLong()).bytes(image, offset, size).toByteArray()
    }

    fun confirmedOffset(payload: ByteArray): Long? = if (payload.size == 4) {
        (payload[0].toLong() and 255) or ((payload[1].toLong() and 255) shl 8) or
            ((payload[2].toLong() and 255) shl 16) or ((payload[3].toLong() and 255) shl 24)
    } else null
}
