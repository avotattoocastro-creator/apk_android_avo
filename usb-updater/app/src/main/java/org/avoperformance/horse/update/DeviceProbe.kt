package org.avoperformance.horse.update

import java.security.MessageDigest

/**
 * BLOQUE A: read-only identification of the connected watch. Everything in the
 * snapshot comes from the chip; every flash read is proved with the ROM's MD5.
 */
internal object DeviceProbe {
    const val PARTITION_TABLE_OFFSET = 0x8000L
    const val PARTITION_TABLE_MAX = 0xC00
    const val SLOT_HEAD_BYTES = 32 + 256

    data class Slot(
        val index: Int,
        val partition: PartitionTable.Entry,
        val headerValid: Boolean,
        val description: String?
    ) {
        val label: String get() = "${partition.name} (ota_$index, 0x%X)".format(partition.offset)
    }

    data class Snapshot(
        val security: EspRom.SecurityInfo,
        val efuseFlashEncryption: Boolean,
        val efuseSecureBoot: Boolean,
        val chipRevisionFull: Int,
        val usbJtagSerial: Boolean,
        val jedec: Triple<Int, Int, Int>,
        val physicalFlash: Long?,
        val bootloaderValid: Boolean,
        val configuredFlash: Long?,
        val partitions: PartitionTable.Result,
        val partitionTableBytes: Int,
        val otadataPartition: PartitionTable.Entry,
        val otadata: List<OtaData.Entry>,
        val slots: List<Slot>,
        val bootSlot: Int?
    ) {
        val chipRevisionText: String get() = "v%d.%d".format(chipRevisionFull / 100, chipRevisionFull % 100)

        fun report(): List<String> = buildList {
            add("Chip: ESP32-S3 (id ${security.chipId}), revisión $chipRevisionText")
            add("USB: " + if (usbJtagSerial) "USB-Serial/JTAG (ROM)" else "otro periférico")
            add("Flash: JEDEC %02X %02X %02X · física %s · bootloader configurado para %s".format(
                jedec.first, jedec.second, jedec.third,
                physicalFlash?.let { "${it shr 20} MB" } ?: "desconocida",
                configuredFlash?.let { "${it shr 20} MB" } ?: "desconocido"))
            add("Seguridad: Secure Boot " + onOff(security.secureBoot) +
                " · Flash Encryption " + onOff(security.flashEncryption) +
                " · Descarga segura " + onOff(security.secureDownload))
            add("Particiones (leídas del reloj, verificadas por MD5):")
            partitions.entries.forEach {
                add("  %-10s tipo %d/0x%02X  0x%06X  %d KB".format(it.name, it.type, it.subtype, it.offset, it.size / 1024))
            }
            otadata.forEachIndexed { i, e ->
                add("otadata[$i]: " + if (e.seq == 0xFFFF_FFFFL) "vacío" else
                    "seq ${e.seq}, estado ${e.stateName}, CRC ${if (e.crcOk) "correcto" else "incorrecto"}")
            }
            add("Slot seleccionado por otadata: " + (bootSlot?.let { slots[it].label } ?: "ninguno (arranque por defecto)"))
            slots.forEach {
                add("  ${it.label}: " + when {
                    !it.headerValid -> "sin imagen válida"
                    it.description.isNullOrBlank() -> "imagen ESP32-S3 (versión no legible)"
                    else -> it.description
                })
            }
        }
    }

    private fun onOff(b: Boolean) = if (b) "ACTIVO" else "desactivado"

    fun flashSizeFromJedec(manufacturer: Int, capacity: Int): Long? {
        if (manufacturer == 0x1F) { // Adesto
            val id = capacity and 0x1F
            return if (id in 0x04..0x09) (512L * 1024) shl (id - 0x04) else null
        }
        return when (capacity) {
            in 0x12..0x1C -> (256L * 1024) shl (capacity - 0x12)
            in 0x20..0x22 -> (64L shl 20) shl (capacity - 0x20)
            in 0x32..0x3A -> (256L * 1024) shl (capacity - 0x32)
            else -> null
        }
    }

    /** esptool ESP32S3ROM get_major/minor_chip_version, as major*100+minor. */
    fun chipRevision(rom: EspRom): Int {
        val w3 = rom.readReg(EspRom.EFUSE_BLOCK1_ADDR + 12)
        val w5 = rom.readReg(EspRom.EFUSE_BLOCK1_ADDR + 20)
        val blk2w4 = rom.readReg(EspRom.EFUSE_BLOCK2_ADDR + 16)
        val minorRaw = (((w5 ushr 23) and 1L) shl 3) or ((w3 ushr 18) and 7L)
        val blkMajor = blk2w4 and 3L
        val blkMinor = (w3 ushr 24) and 7L
        val eco0 = (minorRaw and 7L) == 0L && blkMajor == 1L && blkMinor == 1L
        val major = if (eco0) 0L else (w5 ushr 24) and 3L
        val minor = if (eco0) 0L else minorRaw
        return (major * 100 + minor).toInt()
    }

    private fun md5(b: ByteArray) = hex(MessageDigest.getInstance("MD5").digest(b))

    /** Session setup shared by probe and installer. Requires a synced ROM. */
    data class FlashSetup(val usbJtag: Boolean, val jedec: Triple<Int, Int, Int>, val physical: Long?)

    fun prepare(rom: EspRom): FlashSetup {
        val usbJtag = runCatching { rom.usesUsbJtagSerial() }.getOrDefault(false)
        if (usbJtag) rom.disableWatchdogs()
        rom.spiAttach()
        val jedec = rom.flashJedec()
        val physical = flashSizeFromJedec(jedec.first, jedec.third)
        // 24-bit addressing only: everything this tool touches lies below 16 MB.
        rom.spiSetParams(minOf(physical ?: (4L shl 20), FlashCommands.MAX_FLASH))
        return FlashSetup(usbJtag, jedec, physical)
    }

    fun run(rom: EspRom, log: (String) -> Unit = {}): Snapshot {
        log("Leyendo información de seguridad del chip…")
        val security = rom.securityInfo()
        if (security.secureDownload)
            fail(Failure.UNSAFE, "el chip está en modo de descarga segura (Secure Download): no permite leer la flash")
        if (security.chipId != AppImage.CHIP_ID_ESP32S3.toLong())
            fail(Failure.INCOMPATIBLE, "el chip conectado no es un ESP32-S3 (chip id ${security.chipId})")
        val cryptCnt = ((rom.readReg(EspRom.EFUSE_SPI_BOOT_CRYPT_CNT_REG) ushr 18) and 7L).toInt()
        val efuseEncryption = Integer.bitCount(cryptCnt) % 2 == 1
        val efuseSecureBoot = rom.readReg(EspRom.EFUSE_SECURE_BOOT_EN_REG) and (1L shl 20) != 0L
        val revision = chipRevision(rom)

        log("Configurando acceso a la flash…")
        val (usbJtag, jedec, physical) = prepare(rom)

        log("Leyendo cabecera del bootloader…")
        val boot = rom.readFlashVerified(0, 32)
        val bootValid = AppImage.headerLooksValid(boot)
        val configured = if (bootValid) AppImage.flashSizeBytes((boot[3].toInt() and 0xF0) ushr 4) else null

        log("Leyendo tabla de particiones en 0x8000…")
        val table = readPartitionTable(rom)
        val partitionLimit = minOf(configured ?: physical ?: FlashCommands.MAX_FLASH, physical ?: FlashCommands.MAX_FLASH, FlashCommands.MAX_FLASH)
        val parsed = try { PartitionTable.parse(table, partitionLimit) } catch (e: IllegalArgumentException) {
            fail(Failure.PARTITION, e.message ?: "tabla de particiones inválida")
        }
        val otaPart = parsed.entries.firstOrNull { it.type == 1 && it.subtype == 0 }
            ?: fail(Failure.PARTITION, "no hay partición otadata")
        if (otaPart.size < 2L * OtaData.SECTOR || otaPart.offset % OtaData.SECTOR != 0L)
            fail(Failure.PARTITION, "partición otadata con tamaño o alineación no válidos")

        log("Leyendo otadata…")
        val otadata = listOf(0, 1).map {
            OtaData.Entry(rom.readFlashVerified(otaPart.offset + it * OtaData.SECTOR, OtaData.ENTRY_SIZE))
        }
        val apps = parsed.entries.filter { it.isOtaApp }.sortedBy { it.subtype }
        log("Leyendo cabeceras de los slots de aplicación…")
        val slots = apps.mapIndexed { i, p ->
            val head = rom.readFlashVerified(p.offset, SLOT_HEAD_BYTES)
            Slot(p.subtype - 0x10, p, AppImage.headerLooksValid(head), AppImage.describeHead(head))
        }
        val boot0 = OtaData.bootSlot(otadata, apps.size)
        return Snapshot(security, efuseEncryption, efuseSecureBoot, revision, usbJtag, jedec, physical,
            bootValid, configured, parsed, table.size, otaPart, otadata, slots,
            boot0?.takeIf { idx -> slots.any { it.index == idx } })
    }

    /** Reads rows until the 0xFFFF terminator and proves the bytes with the chip's MD5. */
    fun readPartitionTable(rom: EspRom): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        var off = 0
        var end = -1
        while (off < PARTITION_TABLE_MAX && end < 0) {
            val chunk = rom.readFlashRaw(PARTITION_TABLE_OFFSET + off, 64)
            out.write(chunk)
            for (row in 0 until 2) {
                val p = off + row * 32
                val magic = u16le(chunk, row * 32)
                if (p == 0 && magic != 0x50AA)
                    fail(Failure.PARTITION, "no hay tabla de particiones en 0x8000 (se leyó 0x%04X)".format(magic))
                if (magic == 0xFFFF) { end = p + 32; break }
                if (magic != 0x50AA && magic != 0xEBEB) fail(Failure.PARTITION, "fila $p de la tabla corrupta")
            }
            off += 64
        }
        if (end < 0) fail(Failure.PARTITION, "tabla de particiones sin terminador")
        val bytes = out.toByteArray().copyOf(end)
        if (md5(bytes) == rom.flashMd5(PARTITION_TABLE_OFFSET, end.toLong())) return bytes
        return rom.readFlashVerified(PARTITION_TABLE_OFFSET, end)
    }
}
