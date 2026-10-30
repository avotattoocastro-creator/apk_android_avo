package org.avoperformance.horse.update

/**
 * Decides WHERE the image goes, from live device data only. Never writes.
 *
 * Rules:
 *  - Only an OTA app slot is written, never offset 0x0, the partition table,
 *    NVS, otadata's active copy, blackbox, coredump or any other data partition.
 *  - Normal update: the slot the bootloader currently selects holds a valid
 *    image (it is what runs) -> write the OTHER slot.
 *  - USB recovery: the selected slot has no valid image (the app cannot be
 *    booted from it) -> rewrite that broken slot and keep the other one.
 *  - otadata is changed exactly like esp_ota_set_boot_partition() does, and
 *    only after the written image has been verified.
 */
internal object InstallPlanner {
    enum class Mode(val text: String) {
        NORMAL("Actualización normal"),
        RECOVERY("Recuperación USB")
    }

    data class Plan(
        val mode: Mode,
        val target: DeviceProbe.Slot,
        val preserved: DeviceProbe.Slot?,
        val otaUpdate: OtaData.Update,
        val otadataPartition: PartitionTable.Entry,
        val eraseBytes: Long,
        val notes: List<String>
    ) {
        val otadataSectorAddress: Long get() = otadataPartition.offset + otaUpdate.sector * OtaData.SECTOR.toLong()

        fun summary(): List<String> = buildList {
            add("Modo: ${mode.text}")
            add("Destino: ${target.label}, ${eraseBytes / 1024} KB a borrar de ${target.partition.size / 1024} KB")
            add("Se conserva: " + (preserved?.let { "${it.label} — ${it.description ?: "imagen válida"}" } ?: "ningún slot con imagen válida"))
            add("Activación: otadata[${otaUpdate.sector}] ← seq ${otaUpdate.seq}, estado ${OtaData.stateName(otaUpdate.state)}")
            addAll(notes)
        }
    }

    fun plan(device: DeviceProbe.Snapshot, image: AppImage.Info): Plan {
        val sec = device.security
        // ---- security (never bypassed)
        if (sec.secureDownload) fail(Failure.UNSAFE, "modo de descarga segura activo")
        if (sec.secureBoot || device.efuseSecureBoot)
            fail(Failure.UNSAFE, "Secure Boot está activo: la imagen tendría que estar firmada con la clave del reloj. No se intenta eludir.")
        if (sec.flashEncryption || device.efuseFlashEncryption)
            fail(Failure.UNSAFE, "Flash Encryption está activo: escribir en claro dejaría el reloj sin arrancar. No se intenta eludir.")
        if (sec.secureBoot != device.efuseSecureBoot || sec.flashEncryption != device.efuseFlashEncryption)
            fail(Failure.UNSAFE, "la información de seguridad del ROM y de los eFuses no coincide")

        // ---- chip / image compatibility
        if (sec.chipId != AppImage.CHIP_ID_ESP32S3.toLong()) fail(Failure.INCOMPATIBLE, "el chip no es ESP32-S3")
        if (image.chipId != AppImage.CHIP_ID_ESP32S3) fail(Failure.INCOMPATIBLE, "la imagen no es para ESP32-S3")
        if (image.minChipRevFull != 0xFFFF && device.chipRevisionFull < image.minChipRevFull)
            fail(Failure.INCOMPATIBLE, "la imagen exige revisión de chip ≥ v%d.%d y el reloj es %s".format(
                image.minChipRevFull / 100, image.minChipRevFull % 100, device.chipRevisionText))
        if (image.maxChipRevFull != 0xFFFF && image.maxChipRevFull != 0 && device.chipRevisionFull > image.maxChipRevFull)
            fail(Failure.INCOMPATIBLE, "la imagen admite como máximo la revisión v%d.%d y el reloj es %s".format(
                image.maxChipRevFull / 100, image.maxChipRevFull % 100, device.chipRevisionText))

        // ---- flash / bootloader
        val physical = device.physicalFlash ?: fail(Failure.UNSAFE, "no se pudo identificar la memoria flash (JEDEC desconocido)")
        if (!device.bootloaderValid) fail(Failure.UNSAFE, "no hay un bootloader ESP32-S3 válido en 0x0: la recuperación necesita programación completa")
        val configured = device.configuredFlash ?: fail(Failure.UNSAFE, "tamaño de flash del bootloader desconocido")
        val usable = minOf(physical, configured, FlashCommands.MAX_FLASH)
        val notes = mutableListOf<String>()
        AppImage.flashSizeBytes(image.flashSizeCode)?.let {
            if (it > physical) fail(Failure.INCOMPATIBLE, "la imagen está compilada para ${image.flashSizeText} y la flash del reloj es de ${physical shr 20} MB")
            if (it != configured) notes.add("Aviso: la imagen indica ${image.flashSizeText} y el bootloader ${configured shr 20} MB (el bootloader manda).")
        }

        // ---- partitions
        val slots = device.slots
        if (slots.size != 2 || slots.map { it.index }.sorted() != listOf(0, 1))
            fail(Failure.PARTITION, "se requieren exactamente dos slots OTA (ota_0 y ota_1); hay ${slots.size}")
        val factory = device.partitions.entries.firstOrNull { it.type == 0 && it.subtype == 0x00 }

        val selected: DeviceProbe.Slot? = device.bootSlot?.let { i -> slots.first { it.index == i } }
        val mode: Mode
        val target: DeviceProbe.Slot
        val preserved: DeviceProbe.Slot?
        when {
            selected != null && selected.headerValid -> {
                mode = Mode.NORMAL; target = slots.first { it.index != selected.index }; preserved = selected
            }
            selected != null -> {
                mode = Mode.RECOVERY; target = selected
                preserved = slots.firstOrNull { it.index != selected.index && it.headerValid }
                notes.add("El slot seleccionado (${selected.label}) no contiene una imagen válida: se reescribe ese slot y se conserva el otro.")
            }
            factory != null -> fail(Failure.UNSAFE, "otadata vacío con partición factory: el reloj arranca desde factory. Caso no admitido por seguridad.")
            slots[0].headerValid -> {
                mode = Mode.NORMAL; target = slots[1]; preserved = slots[0]
                notes.add("otadata no selecciona ningún slot: el bootloader arranca ota_0, por eso se escribe ota_1.")
            }
            else -> {
                mode = Mode.RECOVERY; target = slots[0]
                preserved = slots[1].takeIf { it.headerValid }
                notes.add("Ningún slot seleccionado contiene una imagen válida: se graba ota_0.")
            }
        }

        val part = target.partition
        if (part.offset % 0x10000L != 0L) fail(Failure.PARTITION, "${part.name} no está alineada a 64 KB")
        if (part.offset < DeviceProbe.PARTITION_TABLE_OFFSET + 0x1000) fail(Failure.PARTITION, "${part.name} solapa el bootloader o la tabla")
        if (part.offset + part.size > usable) fail(Failure.PARTITION, "${part.name} queda fuera de la flash utilizable")
        if (part.flags != 0L) fail(Failure.UNSAFE, "${part.name} tiene flags (cifrada/solo lectura)")
        if (image.size.toLong() > part.size)
            fail(Failure.INCOMPATIBLE, "el firmware (${image.size} bytes) no cabe en ${part.name} (${part.size} bytes)")
        val erase = (image.size + FlashCommands.SECTOR - 1L) / FlashCommands.SECTOR * FlashCommands.SECTOR
        if (part.offset + erase > part.offset + part.size) fail(Failure.INCOMPATIBLE, "el borrado excedería ${part.name}")
        val others = device.partitions.entries.filter { it !== part }
        if (others.any { part.offset < it.offset + it.size && it.offset < part.offset + erase })
            fail(Failure.UNSAFE, "la región a borrar solapa otra partición")
        if (preserved != null && preserved.index == target.index) fail(Failure.UNSAFE, "el destino coincide con el slot conservado")

        val update = OtaData.planUpdate(device.otadata, target.index, slots.size)
        val active = OtaData.activeIndex(device.otadata)
        if (active >= 0 && update.sector == active && OtaData.bootSlot(device.otadata, slots.size) != target.index)
            fail(Failure.UNSAFE, "la activación sobrescribiría la copia activa de otadata")
        return Plan(mode, target, preserved, update, device.otadataPartition, erase, notes)
    }
}
