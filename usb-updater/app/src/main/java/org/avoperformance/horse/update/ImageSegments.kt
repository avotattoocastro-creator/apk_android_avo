package org.avoperformance.horse.update

/** Checks ESP32 application segment boundaries and XOR checksum. */
internal object ImageSegments {
    fun validate(image: ByteArray): String {
        require(image.size >= 32 && (image[0].toInt() and 255) == 0xE9) { "Cabecera inválida" }
        val count = image[1].toInt() and 255
        require(count in 1..16) { "Número de segmentos inválido" }
        val chip = (image[12].toInt() and 255) or ((image[13].toInt() and 255) shl 8)
        require(chip == 9) { "No es ESP32-S3" }
        var pos = 24
        var xor = 0xEF
        repeat(count) {
            require(pos + 8 <= image.size) { "Segmento truncado" }
            val length = (0..3).fold(0L) { acc, i ->
                acc or ((image[pos + 4 + i].toLong() and 255L) shl (i * 8))
            }
            require(length > 0 && length <= image.size.toLong() - pos - 8) { "Longitud de segmento inválida" }
            for (i in pos + 8 until pos + 8 + length.toInt()) xor = xor xor (image[i].toInt() and 255)
            pos += 8 + length.toInt()
        }
        val checksumAt = ((pos + 15) / 16) * 16 - 1
        require(checksumAt < image.size) { "Checksum ausente" }
        require((image[checksumAt].toInt() and 255) == xor) { "Checksum ESP incorrecto" }
        val extra = image.size - checksumAt - 1
        require(extra == 0 || extra == 32 || extra == 68) { "Tráiler de imagen desconocido" }
        return "ESP32-S3: $count segmentos y checksum correctos; firma criptográfica no verificada"
    }
}
