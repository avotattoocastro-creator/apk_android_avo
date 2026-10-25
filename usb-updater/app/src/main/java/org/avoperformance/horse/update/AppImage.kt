package org.avoperformance.horse.update

import java.security.MessageDigest

/**
 * ESP-IDF application image (esp_image_header_t + segments + checksum + optional
 * SHA-256), checked the way the second-stage bootloader checks it.
 * Layout: esptool bin_image.py (extended header "<BBBBHBHH4BB") and
 * esp_app_desc_t from ESP-IDF.
 */
internal object AppImage {
    const val MAGIC = 0xE9
    const val CHIP_ID_ESP32S3 = 9
    const val CHIP_ID_ESP32C6 = 13
    const val APP_DESC_MAGIC = 0xABCD5432L

    data class Segment(val loadAddress: Long, val fileOffset: Int, val length: Int)

    data class Info(
        val size: Int,
        val sha256: String,
        val segments: List<Segment>,
        val chipId: Int,
        val minChipRevFull: Int,
        val maxChipRevFull: Int,
        val hashAppended: Boolean,
        val flashSizeCode: Int,
        val entry: Long,
        val version: String,
        val projectName: String,
        val idfVersion: String,
        val buildDate: String,
        val secureVersion: Long,
        /** Version of the AVO firmware itself (Arduino builds put the lib-builder hash in esp_app_desc_t). */
        val avoVersion: String? = null,
        /** True when the image carries the AVO chest / Waveshare AMOLED 2.06 identity marker. */
        val avoChestMarker: Boolean = false,
        /** Version of an AVO back-module firmware ("AVO-BACK" marker, V3.8.0+). */
        val avoBackVersion: String? = null,
    ) {
        val isAvoBack: Boolean get() = avoBackVersion != null
        /** "AVO-CHEST 3.7.1-rc2" / "AVO-BACK 3.8.0" style label. */
        val label: String get() = avoBackVersion?.let { "AVO-BACK $it" } ?: avoVersion?.let { "AVO-CHEST $it" }
            ?: listOf(projectName, version).filter { it.isNotBlank() }.joinToString(" ")
        /** Version string the firmware prints at boot (used to confirm the first boot). */
        val runtimeVersion: String get() = avoBackVersion ?: avoVersion ?: version
        val flashSizeText: String get() = flashSizeName(flashSizeCode)
    }

    fun flashSizeName(code: Int): String =
        listOf("1 MB", "2 MB", "4 MB", "8 MB", "16 MB", "32 MB", "64 MB", "128 MB").getOrElse(code) { "?" }

    fun flashSizeBytes(code: Int): Long? = if (code in 0..7) (1L shl 20) shl code else null

    private val semver = Regex("""\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?""")

    /** Null-terminated printable strings in [from, to). */
    private fun strings(b: ByteArray, from: Int, to: Int): Sequence<Pair<Int, String>> = sequence {
        var start = -1
        for (i in from until minOf(to, b.size)) {
            val c = b[i].toInt() and 255
            if (c in 32..126) { if (start < 0) start = i }
            else {
                if (start >= 0 && c == 0 && i - start in 3..40 && (start == 0 || b[start - 1].toInt() == 0))
                    yield(start to String(b, start, i - start, Charsets.US_ASCII))
                start = -1
            }
        }
    }

    /** AVO firmware stores AVO_FW_VERSION right before "AVO-CHEST" (or "AVO-BACK") in its first data segment. */
    fun findAvoVersion(image: ByteArray, limit: Int = 0x20000, marker: String = "AVO-CHEST"): String? {
        val found = strings(image, 0, limit).toList()
        for ((i, pair) in found.withIndex()) {
            if (pair.second != marker) continue
            val prev = found.getOrNull(i - 1) ?: continue
            if (pair.first - (prev.first + prev.second.length) <= 16 && semver.matches(prev.second)) return prev.second
        }
        return null
    }

    fun hasAvoChestMarker(image: ByteArray): Boolean {
        val needles = listOf("AVOCHEST-IMG-V1:WS-AMOLED-2.06", "AVO_CHEST_WAVESHARE_ESP32S3").map { it.toByteArray() }
        return needles.any { n -> indexOf(image, n) >= 0 }
    }

    private fun indexOf(h: ByteArray, n: ByteArray): Int {
        outer@ for (i in 0..h.size - n.size) {
            for (j in n.indices) if (h[i + j] != n[j]) continue@outer
            return i
        }
        return -1
    }

    private fun bad(detail: String): Nothing = fail(Failure.INCOMPATIBLE, detail)

    private fun cString(b: ByteArray, p: Int, max: Int): String {
        if (p + max > b.size) return ""
        val raw = b.copyOfRange(p, p + max)
        val end = raw.indexOf(0).let { if (it < 0) max else it }
        return String(raw, 0, end, Charsets.US_ASCII).filter { it.code in 32..126 }
    }

    /** Header plausibility only (used on flash slots, where only the first bytes are read). */
    fun headerLooksValid(head: ByteArray): Boolean =
        head.size >= 24 && (head[0].toInt() and 255) == MAGIC &&
            (head[1].toInt() and 255) in 1..16 && u16le(head, 12) == CHIP_ID_ESP32S3

    /** Reads the firmware label from the first bytes of a slot (header, app desc, AVO version string). */
    fun describeHead(head: ByteArray): String? {
        if (!headerLooksValid(head)) return null
        findAvoVersion(head, head.size)?.let { return "AVO-CHEST $it" }
        findAvoVersion(head, head.size, "AVO-BACK")?.let { return "AVO-BACK $it" }
        if (head.size < 32 + 256 || u32le(head, 32) != APP_DESC_MAGIC) return null
        return listOf(cString(head, 32 + 48, 32), cString(head, 32 + 16, 32)).filter { it.isNotBlank() }.joinToString(" ")
    }

    /** [expectedChip]: ESP32-S3 for chest/back; ESP32-C6 only for the girth full-image path (GirthImage). */
    fun parse(image: ByteArray, expectedChip: Int = CHIP_ID_ESP32S3): Info {
        if (image.size < 24 + 8 + 16) bad("archivo demasiado pequeño")
        if ((image[0].toInt() and 255) != MAGIC) bad("cabecera ESP inválida (no empieza por 0xE9)")
        val count = image[1].toInt() and 255
        if (count !in 1..16) bad("número de segmentos inválido ($count)")
        val chip = u16le(image, 12)
        if (chip != expectedChip) bad(if (expectedChip == CHIP_ID_ESP32S3) "la imagen no es para ESP32-S3 (chip id $chip)" else "la imagen no es para ESP32-C6 (chip id $chip)")
        val hashAppended = image[23].toInt() == 1
        val segments = ArrayList<Segment>(count)
        var pos = 24
        var xor = FlashCommands.CHECKSUM_MAGIC
        repeat(count) {
            if (pos + 8 > image.size) bad("segmento ${it + 1} truncado")
            val load = u32le(image, pos)
            val len = u32le(image, pos + 4)
            if (len <= 0 || len > image.size.toLong() - pos - 8) bad("longitud del segmento ${it + 1} inválida")
            if (len % 4 != 0L) bad("segmento ${it + 1} no alineado a 4 bytes")
            segments.add(Segment(load, pos + 8, len.toInt()))
            for (i in pos + 8 until pos + 8 + len.toInt()) xor = xor xor (image[i].toInt() and 255)
            pos += 8 + len.toInt()
        }
        // esptool align_file_position(f, 16): the checksum byte sits at the next offset ≡ 15 (mod 16).
        val checksumAt = pos + (15 - pos % 16)
        if (checksumAt >= image.size) bad("falta el checksum de la imagen")
        if ((image[checksumAt].toInt() and 255) != xor) bad("checksum de la imagen incorrecto")
        var end = checksumAt + 1
        if (hashAppended) {
            if (end + 32 > image.size) bad("falta el SHA-256 adjunto")
            val digest = MessageDigest.getInstance("SHA-256").digest(image.copyOfRange(0, end))
            if (!digest.contentEquals(image.copyOfRange(end, end + 32))) bad("SHA-256 adjunto incorrecto: archivo dañado")
            end += 32
        }
        if (end != image.size) {
            bad("${image.size - end} bytes inesperados tras la imagen (¿imagen firmada o archivo combinado?)")
        }
        val desc = segments.first().fileOffset
        val hasDesc = desc + 256 <= image.size && u32le(image, desc) == APP_DESC_MAGIC
        return Info(
            size = image.size,
            sha256 = hex(MessageDigest.getInstance("SHA-256").digest(image)),
            segments = segments,
            chipId = chip,
            minChipRevFull = u16le(image, 15),
            maxChipRevFull = u16le(image, 17),
            hashAppended = hashAppended,
            flashSizeCode = (image[3].toInt() and 0xF0) ushr 4,
            entry = u32le(image, 4),
            version = if (hasDesc) cString(image, desc + 16, 32) else "",
            projectName = if (hasDesc) cString(image, desc + 48, 32) else "",
            idfVersion = if (hasDesc) cString(image, desc + 112, 32) else "",
            buildDate = if (hasDesc) (cString(image, desc + 96, 16) + " " + cString(image, desc + 80, 16)).trim() else "",
            secureVersion = if (hasDesc) u32le(image, desc + 4) else 0,
            avoVersion = findAvoVersion(image),
            avoBackVersion = findAvoVersion(image, image.size, "AVO-BACK"),
            avoChestMarker = hasAvoChestMarker(image)
        )
    }
}
