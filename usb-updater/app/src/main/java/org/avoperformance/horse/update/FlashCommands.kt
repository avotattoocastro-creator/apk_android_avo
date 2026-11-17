package org.avoperformance.horse.update

/**
 * ESP32-S3 ROM serial bootloader command encoding (formats checked against
 * esptool loader.py). Pure encoding: callers decide WHERE to write; see
 * [InstallPlanner] for the safety rules.
 */
internal object FlashCommands {
    const val FLASH_BEGIN = 0x02
    const val FLASH_DATA = 0x03
    const val FLASH_END = 0x04
    const val SYNC = 0x08
    const val WRITE_REG = 0x09
    const val READ_REG = 0x0A
    const val SPI_SET_PARAMS = 0x0B
    const val SPI_ATTACH = 0x0D
    const val FLASH_MD5 = 0x13
    const val GET_SECURITY_INFO = 0x14

    /** ROM flash write block (esptool FLASH_WRITE_SIZE for ROM loaders). */
    const val BLOCK = 0x400
    const val SECTOR = 0x1000
    const val CHECKSUM_MAGIC = 0xEF
    const val MAX_FLASH = 0x1000000L // 24-bit addressing used by this programmer

    fun frame(opcode: Int, payload: ByteArray, checksum: Int = 0): ByteArray =
        RomProtocol.encodeRequest(opcode, payload, checksum)

    fun syncPayload(): ByteArray = byteArrayOf(0x07, 0x07, 0x12, 0x20) + ByteArray(32) { 0x55 }

    /**
     * FLASH_BEGIN. The ESP32-S3 ROM (unlike ESP32/ESP8266) takes a fifth word,
     * "encrypted write" (0 here: flash encryption is refused by the planner).
     * The ROM erases the sectors covering [address, address + imageBytes) up front.
     */
    fun beginPayload(address: Long, imageBytes: Int): ByteArray {
        require(address >= 0 && address % SECTOR == 0L) { "Dirección no alineada a sector: $address" }
        require(imageBytes in 1..MAX_FLASH.toInt()) { "Tamaño inválido: $imageBytes" }
        require(address + imageBytes <= MAX_FLASH) { "Fuera del rango de 16 MB" }
        val blocks = (imageBytes + BLOCK - 1) / BLOCK
        return le32(imageBytes.toLong()) + le32(blocks.toLong()) + le32(BLOCK.toLong()) +
            le32(address) + le32(0)
    }

    fun begin(address: Long, imageBytes: Int): ByteArray = frame(FLASH_BEGIN, beginPayload(address, imageBytes))

    fun checksum(bytes: ByteArray): Int = bytes.fold(CHECKSUM_MAGIC) { sum, b -> sum xor (b.toInt() and 255) }

    fun dataPayload(sequence: Int, bytes: ByteArray): ByteArray {
        require(sequence >= 0 && bytes.size == BLOCK) { "Bloque inválido" }
        return le32(BLOCK.toLong()) + le32(sequence.toLong()) + le32(0) + le32(0) + bytes
    }

    fun data(sequence: Int, bytes: ByteArray): ByteArray =
        frame(FLASH_DATA, dataPayload(sequence, bytes), checksum(bytes))

    fun md5Payload(address: Long, size: Long): ByteArray {
        require(address >= 0 && size > 0 && address + size <= MAX_FLASH) { "Región MD5 inválida" }
        return le32(address) + le32(size) + le32(0) + le32(0)
    }

    fun md5(address: Long, size: Long): ByteArray = frame(FLASH_MD5, md5Payload(address, size))

    fun writeRegPayload(address: Long, value: Long, mask: Long = 0xFFFF_FFFFL, delayUs: Long = 0): ByteArray =
        le32(address) + le32(value and 0xFFFF_FFFFL) + le32(mask) + le32(delayUs)

    /** SPI_ATTACH for the ROM: hspi_arg (0 = default SPI pins) + "is legacy" + 3 reserved bytes. */
    fun spiAttachPayload(): ByteArray = le32(0) + byteArrayOf(0, 0, 0, 0)

    fun spiSetParamsPayload(totalSize: Long): ByteArray =
        le32(0) + le32(totalSize) + le32(64 * 1024L) + le32(SECTOR.toLong()) + le32(256) + le32(0xFFFF)
}
