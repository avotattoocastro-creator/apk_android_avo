package org.avoperformance.horse.update

import java.io.InputStream
import java.security.MessageDigest

/** Reads a selected .bin and validates it completely. Never writes anything. */
internal object FirmwareImage {
    const val MAX_BYTES = FlashCommands.MAX_FLASH

    data class Result(
        val bytes: Long,
        val sha256: String,
        val validHeader: Boolean,
        val chipId: Int?,
        val reason: String,
        val info: AppImage.Info? = null,
        val image: ByteArray? = null,
        /** Full image of the girth unit (ESP32-C6): installed by [GirthInstaller], never by the S3 path. */
        val girth: GirthImage.Info? = null
    )

    fun inspect(input: InputStream): Result {
        val digest = MessageDigest.getInstance("SHA-256")
        val complete = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0L
        input.use { stream ->
            while (true) {
                val n = stream.read(buffer)
                if (n < 0) break
                if (n == 0) continue
                total += n
                require(total <= MAX_BYTES) { "BIN mayor de 16 MB: no es una imagen de aplicación" }
                digest.update(buffer, 0, n)
                complete.write(buffer, 0, n)
            }
        }
        val sha = hex(digest.digest())
        val bytes = complete.toByteArray()
        val chipId = if (bytes.size >= 14 && (bytes[0].toInt() and 255) == AppImage.MAGIC) u16le(bytes, 12) else null
        if (GirthImage.looksLikeGirthFull(bytes)) return try {
            val g = GirthImage.parse(bytes)
            Result(total, sha, true, chipId, "Imagen completa AVO GIRTH ${g.version} para la cincha (ESP32-C6): " +
                g.regions.joinToString(", ") { it.name } + ". La NVS (emparejamiento) no se toca.", g.app, null, g)
        } catch (e: UpdateException) { Result(total, sha, false, chipId, e.message ?: "Imagen de la cincha inválida") }
        return try {
            val info = AppImage.parse(bytes)
            if (bytes.size >= 0x8000 && looksLikeMergedFlashImage(bytes))
                Result(total, sha, false, chipId, "Parece una imagen completa de flash (bootloader en 0x0). Solo se admiten imágenes de aplicación.")
            else Result(total, sha, true, chipId, "Imagen de aplicación ESP32-S3 válida: ${info.segments.size} segmentos, checksum" +
                (if (info.hashAppended) " y SHA-256 adjunto correctos" else " correcto (sin SHA-256 adjunto)") +
                (if (info.avoChestMarker) ". Firmware AVO CHEST para Waveshare AMOLED 2.06\"." else
                    ". AVISO: no lleva la marca AVO CHEST/Waveshare; comprueba que es el firmware del reloj."), info, bytes)
        } catch (e: UpdateException) {
            Result(total, sha, false, chipId, e.message ?: "Imagen inválida")
        }
    }

    /** A bootloader image has an ESP header at 0x0 and a partition table (AA 50) at 0x8000. */
    private fun looksLikeMergedFlashImage(b: ByteArray): Boolean =
        (b[0x8000].toInt() and 255) == 0xAA && (b[0x8001].toInt() and 255) == 0x50
}
