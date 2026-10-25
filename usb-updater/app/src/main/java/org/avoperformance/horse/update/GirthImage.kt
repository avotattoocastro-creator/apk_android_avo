package org.avoperformance.horse.update

/**
 * Full flash image of the AVO GIRTH unit (cincha, ESP32-C6): bootloader at 0x0, partition table at
 * 0x8000, otadata, application at the first OTA slot. This is the ".merged.bin" produced by the build
 * (AVO_GIRTH_*_COMPLETO.bin). Only for chip id 13 (ESP32-C6) and only with the AVO-GIRTH marker:
 * chest and back (ESP32-S3) keep the app-slot-only path with its OTA safety rules.
 *
 * Written regions: bootloader, partition table, otadata and the app. NVS (pairing with the back) and
 * any other data partition are never written, so an update keeps the pairing.
 */
internal object GirthImage {
    const val PARTITION_TABLE_OFFSET = 0x8000
    private const val SECTOR = 0x1000

    data class Region(val name: String, val offset: Int, val length: Int)

    data class Info(
        val version: String,
        val app: AppImage.Info,
        val partitions: List<PartitionTable.Entry>,
        val regions: List<Region>,
        val flashSizeBytes: Long,
        val image: ByteArray,
    ) {
        val label get() = "AVO-GIRTH $version"
        val writeBytes get() = regions.sumOf { it.length.toLong() }
    }

    fun looksLikeGirthFull(b: ByteArray): Boolean =
        b.size > 0x10000 && (b[0].toInt() and 255) == AppImage.MAGIC && u16le(b, 12) == AppImage.CHIP_ID_ESP32C6 &&
            (b[PARTITION_TABLE_OFFSET].toInt() and 255) == 0xAA && (b[PARTITION_TABLE_OFFSET + 1].toInt() and 255) == 0x50

    fun parse(b: ByteArray): Info {
        if (!looksLikeGirthFull(b)) fail(Failure.INCOMPATIBLE, "no es una imagen completa para ESP32-C6")
        val flash = AppImage.flashSizeBytes((b[3].toInt() and 0xF0) ushr 4)
            ?: fail(Failure.INCOMPATIBLE, "tamaño de flash desconocido en la cabecera del bootloader")
        val table = try {
            PartitionTable.parse(b.copyOfRange(PARTITION_TABLE_OFFSET, PARTITION_TABLE_OFFSET + 0xC00), flash).entries
        } catch (e: IllegalArgumentException) { fail(Failure.PARTITION, "tabla de particiones de la imagen: ${e.message}") }
        val app0 = table.firstOrNull { it.type == 0 && it.subtype == 0x10 } ?: fail(Failure.PARTITION, "la imagen no tiene ota_0")
        val otadata = table.first { it.type == 1 && it.subtype == 0x00 }
        if (app0.offset.toInt() >= b.size) fail(Failure.INCOMPATIBLE, "la imagen no contiene la aplicación")
        val appBytes = b.copyOfRange(app0.offset.toInt(), b.size)
        val app = AppImage.parse(appBytes, AppImage.CHIP_ID_ESP32C6)
        if (app.size > app0.size) fail(Failure.INCOMPATIBLE, "la aplicación no cabe en ota_0")
        val version = AppImage.findAvoVersion(appBytes, appBytes.size, "AVO-GIRTH")
            ?: fail(Failure.INCOMPATIBLE, "la imagen ESP32-C6 no lleva la marca AVO-GIRTH: no es el firmware de la cincha")

        // bootloader: up to its last used sector (never into the partition table)
        var bootEnd = PARTITION_TABLE_OFFSET
        while (bootEnd > SECTOR && (bootEnd - SECTOR until bootEnd).all { (b[it].toInt() and 255) == 0xFF }) bootEnd -= SECTOR
        val regions = mutableListOf(
            Region("bootloader", 0, bootEnd),
            Region("tabla de particiones", PARTITION_TABLE_OFFSET, SECTOR),
        )
        if (otadata.offset + otadata.size <= app0.offset)
            regions += Region("otadata", otadata.offset.toInt(), otadata.size.toInt())   // boots ota_0 (where the app goes)
        regions += Region("aplicación (${app0.name})", app0.offset.toInt(), appBytes.size)
        for (r in regions) {
            if (r.offset % SECTOR != 0) fail(Failure.PARTITION, "${r.name} no está alineada a 4 KB")
            if (r.offset + r.length > b.size) fail(Failure.INCOMPATIBLE, "la imagen no contiene ${r.name} completa")
        }
        return Info(version, app, table, regions, flash, b)
    }
}
