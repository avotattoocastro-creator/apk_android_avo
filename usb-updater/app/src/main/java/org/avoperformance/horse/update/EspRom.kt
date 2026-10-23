package org.avoperformance.horse.update

import java.security.MessageDigest

/**
 * Client for the ESP32-S3 ROM serial bootloader over a [RomLink].
 *
 * Every constant here was checked against esptool (loader.py, targets/esp32s3.py).
 * The S3 ROM cannot read flash by itself (READ_FLASH_SLOW is ESP32-only and
 * READ_FLASH needs the stub), so flash is read through the SPI1 controller
 * "user command" registers, the same mechanism esptool uses for flash_id and
 * SFDP. Every read is then checked against the ROM's own SPI_FLASH_MD5, so a
 * wrong register setup can never produce silently wrong data.
 */
internal class EspRom(
    private val link: RomLink,
    private val clock: Clock = Clock.System,
    private val cancelled: () -> Boolean = { false }
) {
    data class Reply(val opcode: Int, val value: Long, val data: ByteArray)

    data class SecurityInfo(
        val flags: Long, val flashCryptCnt: Int, val keyPurposes: List<Int>,
        val chipId: Long, val apiVersion: Long
    ) {
        val secureBoot get() = flags and 1L != 0L
        val secureDownload get() = flags and 4L != 0L
        val flashEncryption get() = Integer.bitCount(flashCryptCnt and 7) % 2 == 1
    }

    private val slip = RomProtocol.SlipStream()
    private val pending = ArrayDeque<ByteArray>()
    private val rxBuffer = ByteArray(16384)

    private fun checkAlive() {
        if (cancelled()) throw UpdateException(Failure.CANCELLED, "cancelada por el usuario")
        if (!link.isOpen) fail(Failure.DISCONNECTED, "se perdió la conexión USB")
    }

    /** Discards anything already buffered or arriving within [ms]. */
    fun drain(ms: Long = 50) {
        pending.clear(); slip.reset()
        val until = clock.nowMs() + ms
        while (clock.nowMs() < until && link.isOpen) {
            if (link.read(rxBuffer, 20) <= 0 && ms <= 20) break
        }
        slip.reset()
    }

    private fun nextFrame(deadline: Long): ByteArray? {
        while (true) {
            pending.removeFirstOrNull()?.let { return it }
            checkAlive()
            val left = deadline - clock.nowMs()
            if (left <= 0) return null
            val n = link.read(rxBuffer, minOf(left, 200L).toInt().coerceAtLeast(1))
            if (n > 0) pending.addAll(slip.feed(rxBuffer, n))
            else if (!link.isOpen) fail(Failure.DISCONNECTED, "se perdió la conexión USB")
        }
    }

    private fun send(opcode: Int, payload: ByteArray, checksum: Int) {
        checkAlive()
        val frame = RomProtocol.encodeRequest(opcode, payload, checksum)
        val sent = link.write(frame, 3000)
        if (sent != frame.size) {
            if (!link.isOpen) fail(Failure.DISCONNECTED, "se perdió la conexión USB")
            fail(Failure.NO_BOOTLOADER, "envío USB incompleto ($sent/${frame.size} bytes, comando 0x%02X)".format(opcode))
        }
    }

    /** Waits for the reply to [opcode]; stale replies to other commands are skipped (esptool behaviour). */
    private fun receive(opcode: Int, timeoutMs: Long): Reply? {
        val deadline = clock.nowMs() + timeoutMs
        repeat(100) {
            val frame = nextFrame(deadline) ?: return null
            if (frame.size < 8 || (frame[0].toInt() and 255) != 1) return@repeat
            val size = u16le(frame, 2)
            if (size != frame.size - 8) return@repeat
            val op = frame[1].toInt() and 255
            val data = frame.copyOfRange(8, frame.size)
            if (op == opcode) return Reply(op, u32le(frame, 4), data)
            if (data.size >= 2 && data[0].toInt() != 0 && (data[1].toInt() and 255) == 0x05) {
                fail(Failure.ROM_ERROR, "el ROM no admite el comando 0x%02X".format(opcode))
            }
        }
        return null
    }

    /**
     * Sends a command and validates the status bytes like esptool check_command:
     * the status byte is the first byte AFTER [respDataLen] bytes of response data,
     * followed by the error code. (The S3 ROM sends 4 status bytes; the last two are reserved.)
     */
    fun command(
        opcode: Int, payload: ByteArray = ByteArray(0), checksum: Int = 0,
        timeoutMs: Long = 3000, respDataLen: Int = 0, attempts: Int = 1
    ): Reply {
        var last: UpdateException? = null
        repeat(attempts) {
            send(opcode, payload, checksum)
            val reply = receive(opcode, timeoutMs)
            if (reply == null) {
                last = UpdateException(Failure.NO_BOOTLOADER, "sin respuesta al comando 0x%02X".format(opcode))
                return@repeat
            }
            val d = reply.data
            if (d.size < respDataLen + 2) {
                last = UpdateException(Failure.ROM_ERROR, "respuesta corta (${d.size} bytes) al comando 0x%02X".format(opcode))
                return@repeat
            }
            val status = d[respDataLen].toInt() and 255
            val error = d[respDataLen + 1].toInt() and 255
            if (status != 0) {
                last = UpdateException(Failure.ROM_ERROR, "comando 0x%02X: ${romError(error)}".format(opcode))
                if (error == 0x05) throw last!! // unsupported/invalid message: retrying is pointless
                return@repeat
            }
            return reply
        }
        throw last ?: UpdateException(Failure.NO_BOOTLOADER, "sin respuesta")
    }

    // ---------------------------------------------------------------- raw frames (flasher stub)

    /** Sends a request without waiting for its reply (MEM_END, READ_FLASH data phase). */
    fun sendOnly(opcode: Int, payload: ByteArray, checksum: Int = 0) = send(opcode, payload, checksum)

    /** Next SLIP frame of any kind (stub greeting, flash data, digest), or null on timeout. */
    fun rawFrame(timeoutMs: Long): ByteArray? = nextFrame(clock.nowMs() + timeoutMs)

    /** Sends one SLIP frame with arbitrary content (READ_FLASH acknowledgements). */
    fun writeFrame(packet: ByteArray) {
        checkAlive()
        val f = RomProtocol.slipEncode(packet)
        if (link.write(f, 3000) != f.size) fail(Failure.DISCONNECTED, "envío USB incompleto")
    }

    /** Parses a frame as a reply to [opcode] (status bytes after [respDataLen]); null if it is something else. */
    fun replyOf(frame: ByteArray, opcode: Int): Reply? {
        if (frame.size < 8 || (frame[0].toInt() and 255) != 1 || (frame[1].toInt() and 255) != opcode) return null
        if (u16le(frame, 2) != frame.size - 8) return null
        return Reply(opcode, u32le(frame, 4), frame.copyOfRange(8, frame.size))
    }

    // ---------------------------------------------------------------- basic commands

    /** SYNC; the ROM answers 8 times, the extra answers are drained. Returns true if a ROM (not a stub) replied. */
    fun sync(attempts: Int = 10): Boolean {
        repeat(attempts) {
            checkAlive()
            drain(30)
            send(FlashCommands.SYNC, FlashCommands.syncPayload(), 0)
            val reply = receive(FlashCommands.SYNC, 300)
            if (reply != null && reply.data.isNotEmpty() && reply.data[0].toInt() == 0) {
                drain(150)
                return reply.value != 0L
            }
            clock.sleep(50)
        }
        fail(Failure.NO_BOOTLOADER, "no hay respuesta SYNC. Mantén BOOT, pulsa y suelta RESET y suelta BOOT")
    }

    fun readReg(address: Long): Long =
        command(FlashCommands.READ_REG, le32(address), attempts = 3).value

    fun writeReg(address: Long, value: Long, mask: Long = 0xFFFF_FFFFL) {
        command(FlashCommands.WRITE_REG, FlashCommands.writeRegPayload(address, value, mask))
    }

    fun securityInfo(): SecurityInfo {
        val r = command(FlashCommands.GET_SECURITY_INFO, respDataLen = 20, attempts = 3).data
        return SecurityInfo(
            u32le(r, 0), r[4].toInt() and 255, (5..11).map { r[it].toInt() and 255 },
            u32le(r, 12), u32le(r, 16)
        )
    }

    fun spiAttach() { command(FlashCommands.SPI_ATTACH, FlashCommands.spiAttachPayload()) }

    fun spiSetParams(totalSize: Long) {
        command(FlashCommands.SPI_SET_PARAMS, FlashCommands.spiSetParamsPayload(totalSize))
    }

    // ---------------------------------------------------------------- USB-Serial-JTAG / watchdogs

    fun usesUsbJtagSerial(): Boolean = readReg(UARTDEV_BUF_NO) and 0xFF == UARTDEV_BUF_NO_USB_JTAG_SERIAL

    /** esptool ESP32S3ROM.disable_watchdogs(): RTC WDT and SWD otherwise reset the chip ~10 s into download mode over USB-Serial-JTAG. */
    fun disableWatchdogs() {
        writeReg(RTC_CNTL_WDTWPROTECT_REG, RTC_CNTL_WDT_WKEY)
        writeReg(RTC_CNTL_WDTCONFIG0_REG, 0)
        writeReg(RTC_CNTL_WDTWPROTECT_REG, 0)
        writeReg(RTC_CNTL_SWD_WPROTECT_REG, RTC_CNTL_SWD_WKEY)
        writeReg(RTC_CNTL_SWD_CONF_REG, readReg(RTC_CNTL_SWD_CONF_REG) or RTC_CNTL_SWD_AUTO_FEED_EN)
        writeReg(RTC_CNTL_SWD_WPROTECT_REG, 0)
    }

    /** esptool ESP32S3ROM.hard_reset(): clear "force download boot" so the reset runs the app. */
    fun clearForceDownloadBoot() {
        runCatching { writeReg(RTC_CNTL_OPTION1_REG, 0, RTC_CNTL_FORCE_DOWNLOAD_BOOT_MASK) }
    }

    // ---------------------------------------------------------------- SPI flash access

    /**
     * esptool run_spiflash_command generalised to read up to 64 bytes (W0..W15).
     * Returns [readBytes] bytes of the flash reply.
     */
    fun spiFlashCommand(cmd: Int, readBytes: Int, address: Long? = null, addressBits: Int = 0): ByteArray {
        require(readBytes in 0..64 && (readBytes == 0 || readBytes % 4 == 0) || readBytes == 3)
        val readBits = readBytes * 8
        val oldUsr = readReg(SPI_USR_REG)
        val oldUsr2 = readReg(SPI_USR2_REG)
        try {
            if (readBits > 0) writeReg(SPI_MISO_DLEN_REG, (readBits - 1).toLong())
            if (addressBits > 0) writeReg(SPI_USR1_REG, (addressBits - 1).toLong() shl SPI_USR_ADDR_LEN_SHIFT)
            var flags = SPI_USR_COMMAND
            if (readBits > 0) flags = flags or SPI_USR_MISO
            if (addressBits > 0) flags = flags or SPI_USR_ADDR
            writeReg(SPI_USR_REG, flags)
            writeReg(SPI_USR2_REG, (7L shl SPI_USR2_COMMAND_LEN_SHIFT) or cmd.toLong())
            if (addressBits > 0) writeReg(SPI_ADDR_REG, address ?: 0) // ESP32-S3: SPI_ADDR_REG_MSB = False
            writeReg(SPI_W0_REG, 0)
            writeReg(SPI_CMD_REG, SPI_CMD_USR)
            var done = false
            for (i in 0 until 10) {
                if (readReg(SPI_CMD_REG) and SPI_CMD_USR == 0L) { done = true; break }
            }
            if (!done) fail(Failure.ROM_ERROR, "el comando SPI 0x%02X no terminó".format(cmd))
            val words = (readBytes + 3) / 4
            val out = ByteArray(words * 4)
            for (w in 0 until words) le32(readReg(SPI_W0_REG + 4L * w)).copyInto(out, 4 * w)
            return out.copyOf(readBytes)
        } finally {
            if (link.isOpen) runCatching {
                writeReg(SPI_USR_REG, oldUsr)
                writeReg(SPI_USR2_REG, oldUsr2)
            }
        }
    }

    /** JEDEC RDID: manufacturer, memory type, capacity. */
    fun flashJedec(): Triple<Int, Int, Int> {
        val id = spiFlashCommand(0x9F, 3)
        return Triple(id[0].toInt() and 255, id[1].toInt() and 255, id[2].toInt() and 255)
    }

    fun readFlashRaw(offset: Long, length: Int, chunk: Int = 64): ByteArray {
        require(chunk in setOf(4, 16, 32, 64))
        require(offset >= 0 && length > 0 && offset + length <= FlashCommands.MAX_FLASH)
        val out = ByteArray(length)
        var done = 0
        while (done < length) {
            val n = minOf(chunk, length - done)
            val size = (n + 3) / 4 * 4
            spiFlashCommand(0x03, size, offset + done, 24).copyInto(out, done, 0, n)
            done += n
        }
        return out
    }

    /**
     * Reads flash and proves the bytes are real: the ROM computes MD5 of the same
     * region directly from flash. Falls back to 4-byte reads (the esptool-proven size)
     * before giving up.
     */
    fun readFlashVerified(offset: Long, length: Int): ByteArray {
        val expected = flashMd5(offset, length.toLong())
        for (chunk in intArrayOf(64, 4)) {
            val data = readFlashRaw(offset, length, chunk)
            if (hex(MessageDigest.getInstance("MD5").digest(data)) == expected) return data
        }
        fail(Failure.VERIFY_FAILED, "la lectura de flash en 0x%X no coincide con el MD5 del chip".format(offset))
    }

    fun flashMd5(address: Long, size: Long): String {
        val timeout = maxOf(3000L, (8_000.0 * size / 1e6).toLong()) + 2000
        val r = command(FlashCommands.FLASH_MD5, FlashCommands.md5Payload(address, size),
            timeoutMs = timeout, respDataLen = 32, attempts = 2).data
        val text = r.copyOf(32).toString(Charsets.US_ASCII)
        if (!text.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' })
            fail(Failure.ROM_ERROR, "respuesta MD5 con formato desconocido")
        return text.lowercase()
    }

    // ---------------------------------------------------------------- flash writing

    fun flashBegin(address: Long, size: Int) {
        // esptool: ROM erases up front, 40 s per MB.
        val timeout = maxOf(3000L, (40_000.0 * size / 1e6).toLong()) + 5000
        command(FlashCommands.FLASH_BEGIN, FlashCommands.beginPayload(address, size), timeoutMs = timeout)
    }

    /** esptool flash_block: up to 3 attempts per block. */
    fun flashData(sequence: Int, block: ByteArray) {
        command(FlashCommands.FLASH_DATA, FlashCommands.dataPayload(sequence, block),
            FlashCommands.checksum(block), timeoutMs = 3000, attempts = 3)
    }

    companion object {
        const val UARTDEV_BUF_NO = 0x3FCEF14CL
        const val UARTDEV_BUF_NO_USB_JTAG_SERIAL = 4L

        const val RTCCNTL_BASE = 0x60008000L
        const val RTC_CNTL_WDTCONFIG0_REG = RTCCNTL_BASE + 0x98
        const val RTC_CNTL_WDTWPROTECT_REG = RTCCNTL_BASE + 0xB0
        const val RTC_CNTL_WDT_WKEY = 0x50D83AA1L
        const val RTC_CNTL_SWD_CONF_REG = RTCCNTL_BASE + 0xB4
        const val RTC_CNTL_SWD_AUTO_FEED_EN = 1L shl 31
        const val RTC_CNTL_SWD_WPROTECT_REG = RTCCNTL_BASE + 0xB8
        const val RTC_CNTL_SWD_WKEY = 0x8F1D312AL
        const val RTC_CNTL_OPTION1_REG = 0x6000812CL
        const val RTC_CNTL_FORCE_DOWNLOAD_BOOT_MASK = 1L

        const val EFUSE_BASE = 0x60007000L
        const val EFUSE_RD_REG_BASE = EFUSE_BASE + 0x30
        const val EFUSE_SPI_BOOT_CRYPT_CNT_REG = EFUSE_BASE + 0x34
        const val EFUSE_SECURE_BOOT_EN_REG = EFUSE_BASE + 0x38
        const val EFUSE_BLOCK1_ADDR = EFUSE_BASE + 0x44
        const val EFUSE_BLOCK2_ADDR = EFUSE_BASE + 0x5C

        const val SPI_REG_BASE = 0x60002000L
        const val SPI_CMD_REG = SPI_REG_BASE + 0x00
        const val SPI_ADDR_REG = SPI_REG_BASE + 0x04
        const val SPI_USR_REG = SPI_REG_BASE + 0x18
        const val SPI_USR1_REG = SPI_REG_BASE + 0x1C
        const val SPI_USR2_REG = SPI_REG_BASE + 0x20
        const val SPI_MOSI_DLEN_REG = SPI_REG_BASE + 0x24
        const val SPI_MISO_DLEN_REG = SPI_REG_BASE + 0x28
        const val SPI_W0_REG = SPI_REG_BASE + 0x58
        const val SPI_CMD_USR = 1L shl 18
        const val SPI_USR_COMMAND = 1L shl 31
        const val SPI_USR_ADDR = 1L shl 30
        const val SPI_USR_MISO = 1L shl 28
        const val SPI_USR2_COMMAND_LEN_SHIFT = 28
        const val SPI_USR_ADDR_LEN_SHIFT = 26

        fun romError(code: Int): String = when (code) {
            0x05 -> "mensaje no válido o no admitido"
            0x06 -> "el ROM no pudo ejecutar la orden"
            0x07 -> "checksum incorrecto en el bloque recibido"
            0x08 -> "error de escritura en flash"
            0x09 -> "error de lectura en flash"
            0x0A -> "longitud de lectura incorrecta"
            0x0B -> "error de descompresión"
            else -> "código de error 0x%02X".format(code)
        }
    }
}
