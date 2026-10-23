package org.avoperformance.horse.update

import java.io.InputStream
import java.security.MessageDigest

/** Strict, read-only ESP image preflight. Not a flash writer. */
internal object FirmwareImage {
    data class Result(val bytes: Long, val sha256: String, val validHeader: Boolean, val chipId: Int?, val reason: String)

    fun inspect(input: InputStream): Result {
        val digest = MessageDigest.getInstance("SHA-256")
        val header = ByteArray(24)
        val complete = java.io.ByteArrayOutputStream()
        var total = 0L
        var captured = 0
        val buffer = ByteArray(8192)
        input.use { stream ->
            while (true) {
                val n = stream.read(buffer)
                if (n < 0) break
                if (n == 0) continue
                digest.update(buffer, 0, n)
                complete.write(buffer, 0, n)
                if (captured < header.size) {
                    val take = minOf(n, header.size - captured)
                    System.arraycopy(buffer, 0, header, captured, take)
                    captured += take
                }
                total += n
                require(total <= 0x600000L) { "BIN mayor de 6 MB: no cabe en los slots históricos" }
            }
        }
        val sha = digest.digest().joinToString("") { "%02x".format(it) }
        val magic = captured == header.size && (header[0].toInt() and 255) == 0xE9
        val segments = if (magic) header[1].toInt() and 255 else 0
        val chipId = if (magic) (header[12].toInt() and 255) or ((header[13].toInt() and 255) shl 8) else null
        val structural = if (magic && segments in 1..16 && chipId == 9 && total > 24)\n            runCatching { ImageSegments.validate(complete.toByteArray()) } else null
        val valid = structural?.isSuccess == true
        val reason = when {
            !magic -> "Cabecera ESP inválida"
            segments !in 1..16 -> "Número de segmentos inválido"
            chipId != 9 -> "Imagen no identificada como ESP32-S3 (chipId=$chipId)"
            total <= 24 -> "Imagen incompleta"
            structural?.isFailure == true -> "Imagen corrupta: ${structural.exceptionOrNull()?.message}"
            else -> "${structural?.getOrNull()}; faltan verificación de firma, flash y OTA"
        }
        return Result(total, sha, valid, chipId, reason)
    }
}
