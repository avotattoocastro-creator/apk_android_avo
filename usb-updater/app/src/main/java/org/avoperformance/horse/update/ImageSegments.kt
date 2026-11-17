package org.avoperformance.horse.update

/** Checks ESP32-S3 application segments, XOR checksum and appended SHA-256 (see [AppImage]). */
internal object ImageSegments {
    fun validate(image: ByteArray): String {
        val info = try { AppImage.parse(image) } catch (e: UpdateException) {
            throw IllegalArgumentException(e.message, e)
        }
        val hash = if (info.hashAppended) "SHA-256 adjunto correcto" else "sin SHA-256 adjunto"
        return "ESP32-S3: ${info.segments.size} segmentos, checksum correcto, $hash"
    }
}
