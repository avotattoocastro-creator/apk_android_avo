package org.avoperformance.horse.update

/**
 * ESP-IDF "otadata" partition: two 4 KB sectors, each starting with an
 * esp_ota_select_entry_t { u32 ota_seq; u8 seq_label[20]; u32 ota_state; u32 crc }.
 * Logic mirrors ESP-IDF bootloader_common_loader.c and esp_ota_ops.c
 * (esp_rewrite_ota_data / compute_ota_seq_for_target_slot). No custom format.
 */
internal object OtaData {
    const val ENTRY_SIZE = 32
    const val SECTOR = 0x1000

    const val STATE_NEW = 0x0L
    const val STATE_PENDING_VERIFY = 0x1L
    const val STATE_VALID = 0x2L
    const val STATE_INVALID = 0x3L
    const val STATE_ABORTED = 0x4L
    const val STATE_UNDEFINED = 0xFFFF_FFFFL

    data class Entry(val raw: ByteArray) {
        init { require(raw.size == ENTRY_SIZE) }
        val seq: Long get() = u32le(raw, 0)
        val state: Long get() = u32le(raw, 24)
        val crc: Long get() = u32le(raw, 28)
        val crcOk: Boolean get() = crc == seqCrc(seq)
        /** bootloader_common_ota_select_invalid */
        val invalid: Boolean get() = seq == 0xFFFF_FFFFL || state == STATE_INVALID || state == STATE_ABORTED
        /** bootloader_common_ota_select_valid */
        val valid: Boolean get() = !invalid && crcOk
        val stateName: String get() = stateName(state)
    }

    fun stateName(s: Long): String = when (s) {
        STATE_NEW -> "NEW"
        STATE_PENDING_VERIFY -> "PENDING_VERIFY"
        STATE_VALID -> "VALID"
        STATE_INVALID -> "INVALID"
        STATE_ABORTED -> "ABORTED"
        STATE_UNDEFINED -> "UNDEFINED"
        else -> "0x%08X".format(s)
    }

    private val table = LongArray(256) { n ->
        var c = n.toLong()
        repeat(8) { c = if (c and 1L != 0L) 0xEDB88320L xor (c ushr 1) else c ushr 1 }
        c
    }

    /** zlib crc32(data, start); ESP-IDF calls esp_rom_crc32_le(UINT32_MAX, ...), i.e. Python binascii.crc32(data, 0xFFFFFFFF). */
    fun crc32(data: ByteArray, start: Long = 0xFFFF_FFFFL): Long {
        var c = start.inv() and 0xFFFF_FFFFL
        for (b in data) c = table[((c xor b.toLong()) and 0xFF).toInt()] xor (c ushr 8)
        return c.inv() and 0xFFFF_FFFFL
    }

    fun seqCrc(seq: Long): Long = crc32(le32(seq))

    /** bootloader_common_select_otadata(max = true): index of the active copy or -1. */
    fun activeIndex(e: List<Entry>): Int {
        require(e.size == 2)
        val v0 = e[0].valid
        val v1 = e[1].valid
        return when {
            v0 && v1 -> if (maxOf(e[0].seq, e[1].seq) == e[0].seq) 0 else 1
            v0 -> 0
            v1 -> 1
            else -> -1
        }
    }

    /** OTA slot index (0-based) the bootloader will select from otadata, or null if otadata selects none. */
    fun bootSlot(e: List<Entry>, appCount: Int): Int? {
        val a = activeIndex(e)
        return if (a < 0 || appCount <= 0) null else ((e[a].seq - 1) % appCount).toInt()
    }

    /** compute_ota_seq_for_target_slot (esp_ota_ops.c). */
    fun computeSeq(currentSeq: Long, slot: Int, appCount: Int): Long {
        require(appCount > 0 && slot in 0 until appCount)
        val base = ((slot + 1) % appCount).toLong()
        var i = 0L
        while (currentSeq > base + i * appCount) i++
        return base + i * appCount
    }

    data class Update(val sector: Int, val entry: ByteArray, val seq: Long, val state: Long) {
        /** Full 4 KB sector content to program (entry followed by erased 0xFF). */
        fun sectorImage(): ByteArray = ByteArray(SECTOR) { 0xFF.toByte() }.also { entry.copyInto(it) }
    }

    /**
     * esp_rewrite_ota_data(): which sector to rewrite and with what. The other
     * sector (the currently active copy) is never touched, so an interruption
     * leaves the previous selection intact.
     */
    fun planUpdate(e: List<Entry>, targetSlot: Int, appCount: Int, state: Long = STATE_NEW): Update {
        require(appCount > 0 && targetSlot in 0 until appCount)
        val active = activeIndex(e)
        val sector: Int
        val seq: Long
        if (active != -1) {
            val current = ((e[active].seq - 1) % appCount).toInt()
            if (current == targetSlot) { sector = active; seq = e[active].seq }
            else { sector = active.inv() and 1; seq = computeSeq(e[active].seq, targetSlot, appCount) }
        } else { sector = 0; seq = (targetSlot + 1).toLong() }
        val entry = e[sector].raw.copyOf()
        le32(seq).copyInto(entry, 0)
        le32(state).copyInto(entry, 24)
        le32(seqCrc(seq)).copyInto(entry, 28)
        return Update(sector, entry, seq, state)
    }

    enum class BootCheck(val confirmed: Boolean?, val text: String) {
        CONFIRMED(true, "El nuevo firmware arrancó y se marcó como válido (estado VALID)."),
        RUNNING_UNCONFIRMED(null, "El bootloader cargó el nuevo firmware pero la aplicación aún no lo confirmó (PENDING_VERIFY)."),
        NO_ROLLBACK_INFO(null, "El bootloader no usa rollback (estado NEW sin cambios): el arranque solo se confirma por la salida USB del firmware."),
        ROLLED_BACK(false, "El nuevo firmware no se confirmó y el bootloader volvió al anterior (ABORTED/INVALID)."),
        NOT_SELECTED(false, "otadata ya no selecciona el slot instalado.")
    }

    /** Interprets otadata read back after the first boot of the new image. */
    fun checkAfterBoot(e: List<Entry>, targetSlot: Int, appCount: Int, expectedSeq: Long): BootCheck {
        val written = e.firstOrNull { it.seq == expectedSeq && it.crcOk }
        if (written != null && (written.state == STATE_ABORTED || written.state == STATE_INVALID)) return BootCheck.ROLLED_BACK
        if (bootSlot(e, appCount) != targetSlot || written == null) return BootCheck.NOT_SELECTED
        return when (written.state) {
            STATE_VALID, STATE_UNDEFINED -> if (written.state == STATE_VALID) BootCheck.CONFIRMED else BootCheck.NO_ROLLBACK_INFO
            STATE_PENDING_VERIFY -> BootCheck.RUNNING_UNCONFIRMED
            else -> BootCheck.NO_ROLLBACK_INFO
        }
    }
}
