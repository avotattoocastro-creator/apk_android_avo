package org.avoperformance.horse.update

/**
 * Safe OTA destination selection. Only produces a plan; NEVER writes flash.
 * Active slot and protection flags must come from the connected device.
 */
internal object OtaPlan {
    data class DeviceState(
        val activeSubtype: Int?,
        val partitionTableVerifiedFromDevice: Boolean,
        val flashEncryptionDisabled: Boolean?,
        val secureBootDisabled: Boolean?,
        val flashSize: Long?
    )
    data class Plan(val target: PartitionTable.Entry, val active: PartitionTable.Entry)

    fun select(
        partitions: PartitionTable.Result,
        firmware: FirmwareImage.Result,
        device: DeviceState
    ): Plan {
        require(device.partitionTableVerifiedFromDevice) { "Tabla no leída y verificada en el reloj" }
        require(device.flashEncryptionDisabled == true) { "Estado de cifrado de flash desconocido o activo" }
        require(device.secureBootDisabled == true) { "Estado de Secure Boot desconocido o activo" }
        require(firmware.validHeader) { "BIN ESP32-S3 inválido" }
        require(device.flashSize != null) { "Tamaño real de flash desconocido" }
        val slots = partitions.entries.filter { it.isOtaApp }.sortedBy { it.subtype }
        require(slots.size == 2) { "Se requieren exactamente dos slots OTA" }
        val active = slots.singleOrNull { it.subtype == device.activeSubtype }
            ?: error("No se conoce con certeza el slot activo")
        val target = slots.single { it.subtype != active.subtype }
        require(firmware.bytes <= target.size) { "El BIN no cabe en el slot inactivo" }
        require(target.offset % 0x10000L == 0L && target.size % 0x1000L == 0L) {
            "Partición OTA sin alineación adecuada"
        }
        require(target.offset + target.size <= device.flashSize) { "Slot fuera de la flash física" }
        require(target.flags == 0L) { "Partición OTA con flags no admitidos" }
        require(partitions.entries.none {
            it !== target && target.offset < it.offset + it.size && it.offset < target.offset + target.size
        }) { "Slot OTA solapado" }
        return Plan(target, active)
    }
}
