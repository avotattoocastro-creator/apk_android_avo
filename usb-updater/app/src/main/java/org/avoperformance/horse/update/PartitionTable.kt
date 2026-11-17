package org.avoperformance.horse.update

/**
 * Parses ESP-IDF partition table bytes obtained from the device flash.
 * Parsing does not read or write flash. All offsets are untrusted until
 * the table is read from the connected device and independently verified.
 */
internal object PartitionTable {
    data class Entry(
        val name: String, val type: Int, val subtype: Int,
        val offset: Long, val size: Long, val flags: Long
    ) {
        val isOtaApp: Boolean get() = type == 0 && subtype in 0x10..0x1F
    }

    data class Result(val entries: List<Entry>, val hasMd5Record: Boolean)

    fun parse(bytes: ByteArray, flashSize: Long): Result {
        require(bytes.size >= 64 && bytes.size % 32 == 0) { "Tabla incompleta" }
        require(flashSize in 0x100000L..0x100000000L) { "Tamaño de flash inválido" }
        fun u16(p: Int) = (bytes[p].toInt() and 255) or ((bytes[p + 1].toInt() and 255) shl 8)
        fun u32(p: Int): Long = (0..3).fold(0L) { a, i -> a or ((bytes[p + i].toLong() and 255L) shl (8 * i)) }
        val entries = mutableListOf<Entry>()
        var terminated = false
        var md5 = false
        var md5Valid = false
        for (p in bytes.indices step 32) {
            val magic = u16(p)
            if (magic == 0xFFFF) { terminated = true; break }
            if (magic == 0xEBEB) {
                require(p + 32 <= bytes.size) { "Registro MD5 incompleto" }
                md5 = true
                require(bytes[p + 2] == 0xFF.toByte() && bytes[p + 3] == 0xFF.toByte()) {
                    "Registro MD5 inválido"
                }
                val md = java.security.MessageDigest.getInstance("MD5")
                val expected = md.digest(bytes.copyOfRange(0, p))
                require(expected.contentEquals(bytes.copyOfRange(p + 16, p + 32))) {
                    "Checksum MD5 de particiones incorrecto"
                }
                md5Valid = true
                continue
            }
            require(magic == 0x50AA) { "Magic de partición incorrecto en $p" }
            val type = bytes[p + 2].toInt() and 255
            val subtype = bytes[p + 3].toInt() and 255
            val offset = u32(p + 4)
            val size = u32(p + 8)
            val labelBytes = bytes.copyOfRange(p + 12, p + 28)
            val label = String(labelBytes.takeWhile { it.toInt() != 0 }.toByteArray(), Charsets.US_ASCII)
            require(label.isNotBlank() && label.all { it.code in 32..126 }) { "Etiqueta inválida" }
            require(size > 0 && offset + size <= flashSize && offset + size > offset) { "Partición fuera de flash: $label" }
            require(entries.none { offset < it.offset + it.size && it.offset < offset + size }) { "Particiones solapadas" }
            entries.add(Entry(label, type, subtype, offset, size, u32(p + 28)))
        }
        require(!md5 || md5Valid) { "MD5 sin verificar" }
        require(terminated && entries.isNotEmpty()) { "Tabla sin terminador" }
        require(entries.count { it.isOtaApp } >= 2) { "No hay dos slots OTA" }
        require(entries.any { it.type == 1 && it.subtype == 0x02 }) { "Falta NVS" }
        require(entries.any { it.type == 1 && it.subtype == 0x00 }) { "Falta otadata" }
        return Result(entries, md5)
    }
}
