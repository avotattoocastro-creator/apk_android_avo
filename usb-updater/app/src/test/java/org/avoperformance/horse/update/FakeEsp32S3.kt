package org.avoperformance.horse.update

import java.security.MessageDigest

/** Simulated time: sleeps and read timeouts advance it instantly. */
class FakeClock : Clock {
    var now = 1_000L
    override fun nowMs() = now
    override fun sleep(ms: Long) { if (ms > 0) now += ms }
}

/**
 * SIMULATED ESP32-S3 (ROM download mode + ESP-IDF bootloader + application).
 * Implements the ROM serial protocol as documented by esptool: 4 status bytes,
 * 5-word FLASH_BEGIN, per-block checksum and sequence, MD5 over real flash
 * contents, SPI1 user commands through registers, USB-Serial-JTAG DTR/RTS reset.
 * Flash is NOR-like: programming can only clear bits, so writing without the
 * proper erase is detected.
 *
 * Results obtained with this class are SIMULATION results, not hardware results.
 */
internal class FakeEsp32S3(val clock: FakeClock = FakeClock()) {
    enum class Mode { ROM, APP, OFF }

    val flashSize = 0x1000000
    val flash = ByteArray(flashSize) { 0xFF.toByte() }
    var jedec = Triple(0xC8, 0x40, 0x19) // GD25Q256: 32 MB
    var mode = Mode.ROM
    var securityFlags = 0L
    var cryptCnt = 0
    var efuseCryptCnt = 0
    var efuseSecureBoot = false
    var chipId = 9L

    // bootloader / application behaviour
    var rollbackEnabled = true
    var appConfirms = true
    var appPrintsVersion = true
    /** Return false to make a given app version crash right after boot. */
    var appHealthy: (String) -> Boolean = { true }
    var bootedSlot: Int? = null
    var boots = 0

    // fault injection
    var disconnectAfterDataBlocks = -1
    var corruptMd5Once = false
    var corruptSpiReadsWithChunk64 = false
    var dropEveryNthReply = 0
    var fragmentReplies = true
    var ignoreSync = false

    // observation
    val erasedRegions = mutableListOf<LongRange>()
    val writeRanges = mutableListOf<LongRange>()
    var dataBlocks = 0
    var watchdogsDisabled = false
    var lastFlashBeginPayloadSize = -1

    private val regs = HashMap<Long, Long>()
    private var spiAttached = false
    private var paramsSize = 0L
    private var writeOffset = 0L
    private var writeEnd = 0L
    private var expectedSeq = 0
    private var replyCounter = 0
    private var presentAt = 0L
    private var appBootTime = 0L
    private var link: Link? = null
    private var dtr = false
    private var rts = false
    private var prevState = Pair(false, false)
    private var resetHeldFrom: Pair<Boolean, Boolean>? = null

    val port = object : DevicePort {
        override fun open(timeoutMs: Long): RomLink {
            val deadline = clock.now + timeoutMs
            while (clock.now < deadline) {
                tickApp()
                if (mode != Mode.OFF && clock.now >= presentAt) {
                    link?.closedByDevice = true
                    return Link().also { link = it }
                }
                clock.sleep(50)
            }
            throw UpdateException(Failure.DISCONNECTED, "dispositivo simulado ausente")
        }
    }

    inner class Link : RomLink {
        var closedByDevice = false
        private var closedByHost = false
        private val inbound = ArrayDeque<Byte>()
        private val slip = RomProtocol.SlipStream()
        override val isOpen get() = !closedByDevice && !closedByHost

        fun push(bytes: ByteArray) { if (isOpen) bytes.forEach { inbound.addLast(it) } }

        override fun write(data: ByteArray, timeoutMs: Int): Int {
            if (!isOpen) return -1
            if (mode == Mode.ROM) for (f in slip.feed(data)) handle(f)
            return data.size
        }

        override fun read(buffer: ByteArray, timeoutMs: Int): Int {
            tickApp()
            if (!isOpen) return -1
            if (inbound.isEmpty()) { clock.sleep(timeoutMs.toLong()); tickApp(); if (inbound.isEmpty()) return 0 }
            val max = if (fragmentReplies) minOf(buffer.size, 7) else buffer.size
            var n = 0
            while (n < max && inbound.isNotEmpty()) buffer[n++] = inbound.removeFirst()
            return n
        }

        override fun setLines(dtr: Boolean, rts: Boolean): Boolean {
            if (!isOpen) return false
            lines(dtr, rts)
            return true
        }

        override fun close() { closedByHost = true }
    }

    // ------------------------------------------------------------------ reset logic (USB-Serial-JTAG)

    private fun lines(newDtr: Boolean, newRts: Boolean) {
        val state = Pair(newDtr, newRts)
        if (state == Pair(false, true) && resetHeldFrom == null) resetHeldFrom = prevState
        if (state == Pair(false, false) && resetHeldFrom != null) {
            val download = resetHeldFrom == Pair(true, true)
            resetHeldFrom = null
            chipReset(if (download) Mode.ROM else Mode.APP)
        }
        prevState = state; dtr = newDtr; rts = newRts
    }

    private fun disconnect() { link?.closedByDevice = true; link = null }

    fun chipReset(next: Mode) {
        disconnect()
        spiAttached = false
        watchdogsDisabled = false
        presentAt = clock.now + 300
        if (next == Mode.ROM) { mode = Mode.ROM; return }
        if ((regs[EspRom.RTC_CNTL_OPTION1_REG] ?: 0L) and 1L != 0L) { mode = Mode.ROM; return }
        bootloader()
    }

    // ------------------------------------------------------------------ ESP-IDF bootloader + app model

    private fun table(): PartitionTable.Result? = runCatching {
        var end = 0x8000
        while (u16le(flash, end) != 0xFFFF) end += 32
        PartitionTable.parse(flash.copyOfRange(0x8000, end + 32), flashSize.toLong())
    }.getOrNull()

    private fun otadataEntries(base: Int) = listOf(0, 1).map { OtaData.Entry(flash.copyOfRange(base + it * 0x1000, base + it * 0x1000 + 32)) }

    private fun writeEntry(base: Int, i: Int, e: ByteArray) {
        val p = base + i * 0x1000
        for (k in 0 until 0x1000) flash[p + k] = 0xFF.toByte()
        e.copyInto(flash, p)
    }

    fun slotImage(offset: Long): AppImage.Info? = runCatching {
        // find the image length from the segment headers, then validate exactly that much
        val o = offset.toInt()
        val count = flash[o + 1].toInt() and 255
        var pos = 24
        repeat(count) { pos += 8 + u32le(flash, o + pos + 4).toInt() }
        var end = pos + (15 - pos % 16) + 1
        if (flash[o + 23].toInt() == 1) end += 32
        AppImage.parse(flash.copyOfRange(o, o + end))
    }.getOrNull()

    private fun bootloader() {
        boots++
        val t = table() ?: run { mode = Mode.APP; bootedSlot = null; return }
        val apps = t.entries.filter { it.isOtaApp }.sortedBy { it.subtype }
        val od = t.entries.first { it.type == 1 && it.subtype == 0 }
        val base = od.offset.toInt()
        var e = otadataEntries(base)
        if (rollbackEnabled) for (i in 0..1) if (e[i].state == OtaData.STATE_PENDING_VERIFY) {
            val raw = e[i].raw.copyOf(); le32(OtaData.STATE_ABORTED).copyInto(raw, 24); writeEntry(base, i, raw)
        }
        e = otadataEntries(base)
        val active = OtaData.activeIndex(e)
        var index = if (active < 0) 0 else ((e[active].seq - 1) % apps.size).toInt()
        if (rollbackEnabled && active >= 0 && e[active].state == OtaData.STATE_NEW) {
            val raw = e[active].raw.copyOf(); le32(OtaData.STATE_PENDING_VERIFY).copyInto(raw, 24); writeEntry(base, active, raw)
        }
        var info = slotImage(apps[index].offset)
        if (info == null) { index = 1 - index; info = slotImage(apps[index].offset) }
        bootedSlot = if (info != null) index else null
        mode = Mode.APP
        appBootTime = clock.now
        appStarted = false
        pendingConfirmBase = base
    }

    private var appStarted = false
    private var pendingConfirmBase = 0

    /** Advances the application: prints, confirms (esp_ota_mark_app_valid_cancel_rollback) or crashes. */
    private fun tickApp() {
        if (mode != Mode.APP || clock.now < presentAt) return
        val slot = bootedSlot ?: return
        val t = table() ?: return
        val apps = t.entries.filter { it.isOtaApp }.sortedBy { it.subtype }
        val info = slotImage(apps[slot].offset) ?: return
        if (!appHealthy(info.runtimeVersion)) {
            if (clock.now - appBootTime > 1500) chipReset(Mode.APP)
            return
        }
        if (!appStarted && clock.now - appBootTime > 500) {
            appStarted = true
            if (appPrintsVersion) link?.push("\r\n${info.label} arrancado\r\n".toByteArray())
            if (rollbackEnabled && appConfirms) {
                val e = otadataEntries(pendingConfirmBase)
                val a = OtaData.activeIndex(e)
                if (a >= 0 && e[a].state == OtaData.STATE_PENDING_VERIFY) {
                    val raw = e[a].raw.copyOf(); le32(OtaData.STATE_VALID).copyInto(raw, 24); writeEntry(pendingConfirmBase, a, raw)
                }
            }
        }
    }

    // ------------------------------------------------------------------ ROM command processing

    private fun reply(op: Int, value: Long, data: ByteArray, status: Int = 0, error: Int = 0) {
        replyCounter++
        if (dropEveryNthReply > 0 && replyCounter % dropEveryNthReply == 0) return
        val body = data + byteArrayOf(status.toByte(), error.toByte(), 0, 0)
        val packet = byteArrayOf(1, op.toByte(), (body.size and 255).toByte(), (body.size ushr 8).toByte()) + le32(value) + body
        link?.push(RomProtocol.slipEncode(packet))
    }

    private fun error(op: Int, code: Int) = reply(op, 0, ByteArray(0), 1, code)

    private fun readReg(a: Long): Long = when (a) {
        EspRom.UARTDEV_BUF_NO -> 4L
        EspRom.EFUSE_SPI_BOOT_CRYPT_CNT_REG -> (efuseCryptCnt.toLong() and 7L) shl 18
        EspRom.EFUSE_SECURE_BOOT_EN_REG -> if (efuseSecureBoot) 1L shl 20 else 0L
        EspRom.EFUSE_BLOCK1_ADDR + 12 -> 2L shl 18          // minor revision 2
        EspRom.EFUSE_BLOCK1_ADDR + 20 -> 0L                 // major 0
        EspRom.EFUSE_BLOCK2_ADDR + 16 -> 1L
        else -> regs[a] ?: 0L
    }

    private fun writeReg(a: Long, v: Long, mask: Long) {
        val old = regs[a] ?: 0L
        regs[a] = (old and mask.inv()) or (v and mask) and 0xFFFF_FFFFL
        if (a == EspRom.RTC_CNTL_WDTCONFIG0_REG && v == 0L) watchdogsDisabled = true
        if (a == EspRom.SPI_CMD_REG && v and EspRom.SPI_CMD_USR != 0L) { spiExecute(); regs[a] = 0L }
    }

    private fun spiExecute() {
        if (!spiAttached) return
        val usr = regs[EspRom.SPI_USR_REG] ?: 0L
        val cmd = ((regs[EspRom.SPI_USR2_REG] ?: 0L) and 0xFF).toInt()
        val bits = if (usr and EspRom.SPI_USR_MISO != 0L) ((regs[EspRom.SPI_MISO_DLEN_REG] ?: 0L) + 1).toInt() else 0
        val out = ByteArray(64)
        when (cmd) {
            0x9F -> { out[0] = jedec.first.toByte(); out[1] = jedec.second.toByte(); out[2] = jedec.third.toByte() }
            0x03 -> {
                require(usr and EspRom.SPI_USR_ADDR != 0L)
                require(((regs[EspRom.SPI_USR1_REG] ?: 0L) ushr 26) == 23L) { "address length must be 24 bits" }
                val addr = ((regs[EspRom.SPI_ADDR_REG] ?: 0L) and 0xFFFFFF).toInt()
                for (i in 0 until bits / 8) out[i] = flash[(addr + i) % flashSize]
                if (corruptSpiReadsWithChunk64 && bits == 512) out[5] = (out[5].toInt() xor 0x10).toByte()
            }
        }
        for (w in 0 until 16) regs[EspRom.SPI_W0_REG + 4L * w] = u32le(out, 4 * w)
    }

    private fun md5(a: Long, s: Long): String =
        hex(MessageDigest.getInstance("MD5").digest(flash.copyOfRange(a.toInt(), (a + s).toInt())))

    private fun handle(f: ByteArray) {
        if (f.size < 8 || f[0].toInt() != 0) return
        val op = f[1].toInt() and 255
        val size = u16le(f, 2)
        if (size != f.size - 8) return
        val chk = u32le(f, 4)
        val d = f.copyOfRange(8, f.size)
        when (op) {
            FlashCommands.SYNC -> if (!ignoreSync) repeat(8) { reply(op, 0x20120707L, ByteArray(0)) }
            FlashCommands.READ_REG -> reply(op, readReg(u32le(d, 0)), ByteArray(0))
            FlashCommands.WRITE_REG -> {
                for (p in d.indices step 16) writeReg(u32le(d, p), u32le(d, p + 4), u32le(d, p + 8))
                reply(op, 0, ByteArray(0))
            }
            FlashCommands.GET_SECURITY_INFO -> {
                val r = le32(securityFlags) + byteArrayOf(cryptCnt.toByte()) + ByteArray(7) + le32(chipId) + le32(0)
                reply(op, 0, r)
            }
            FlashCommands.SPI_ATTACH -> if (d.size == 8) { spiAttached = true; reply(op, 0, ByteArray(0)) } else error(op, 0x05)
            FlashCommands.SPI_SET_PARAMS -> if (d.size == 24) { paramsSize = u32le(d, 4); reply(op, 0, ByteArray(0)) } else error(op, 0x05)
            FlashCommands.FLASH_BEGIN -> {
                lastFlashBeginPayloadSize = d.size
                if (d.size != 20 || !spiAttached) return error(op, 0x05)
                val sz = u32le(d, 0); val off = u32le(d, 12)
                if (off % 0x1000 != 0L || off + sz > paramsSize) return error(op, 0x06)
                val end = (off + sz + 0xFFF) / 0x1000 * 0x1000
                for (i in off until end) flash[i.toInt()] = 0xFF.toByte()
                erasedRegions.add(off until end)
                writeOffset = off; writeEnd = end; expectedSeq = 0
                reply(op, 0, ByteArray(0))
            }
            FlashCommands.FLASH_DATA -> {
                val len = u32le(d, 0).toInt(); val seq = u32le(d, 4).toInt()
                val data = d.copyOfRange(16, d.size)
                if (data.size != len) return error(op, 0x05)
                if ((chk and 0xFF).toInt() != FlashCommands.checksum(data)) return error(op, 0x07)
                if (seq == expectedSeq - 1) return reply(op, 0, ByteArray(0)) // duplicate of a retried block
                if (seq != expectedSeq) return error(op, 0x06)
                val at = writeOffset + seq.toLong() * len
                if (at + len > writeEnd) return error(op, 0x08)
                for (i in 0 until len) flash[(at + i).toInt()] = (flash[(at + i).toInt()].toInt() and data[i].toInt()).toByte()
                writeRanges.add(at until at + len)
                expectedSeq++
                dataBlocks++
                if (disconnectAfterDataBlocks in 1..dataBlocks) { mode = Mode.OFF; disconnect(); return }
                reply(op, 0, ByteArray(0))
            }
            FlashCommands.FLASH_MD5 -> {
                var h = md5(u32le(d, 0), u32le(d, 4))
                if (corruptMd5Once) { corruptMd5Once = false; h = (if (h[0] == '0') "1" else "0") + h.substring(1) }
                reply(op, 0, h.toByteArray(Charsets.US_ASCII))
            }
            else -> error(op, 0x05)
        }
    }

    // ------------------------------------------------------------------ setup helpers

    fun writeBootloader() {
        val boot = TestImages.build("bootloader", "bootloader", 0x5000)
        boot[3] = ((4 shl 4) or (boot[3].toInt() and 0x0F)).toByte() // 16 MB in the header
        boot.copyInto(flash, 0)
    }

    fun writePartitionTable(rows: List<PartitionTable.Entry>, withMd5: Boolean = true) {
        val bytes = TestImages.partitionTable(rows, withMd5)
        bytes.copyInto(flash, 0x8000)
    }

    fun writeImage(offset: Long, image: ByteArray) { image.copyInto(flash, offset.toInt()) }

    fun setOtadata(slot: Int, seq: Long, state: Long, sector: Int = 0) {
        val e = ByteArray(32) { 0xFF.toByte() }
        le32(seq).copyInto(e, 0); le32(state).copyInto(e, 24); le32(OtaData.seqCrc(seq)).copyInto(e, 28)
        writeEntry(0xE000, sector, e)
    }

    fun region(offset: Long, size: Int): ByteArray = flash.copyOfRange(offset.toInt(), offset.toInt() + size)
}

internal object TestImages {
    /** Builds a valid ESP32-S3 application image with esp_app_desc_t and appended SHA-256. */
    fun build(version: String, project: String = "AVO-CHEST", approxSize: Int = 200_000, seed: Int = 1,
              arduinoStyle: Boolean = false): ByteArray {
        val rnd = java.util.Random(seed.toLong())
        val desc = ByteArray(256)
        le32(AppImage.APP_DESC_MAGIC).copyInto(desc, 0)
        (if (arduinoStyle) "6671d0b" else version).toByteArray().copyInto(desc, 16)
        (if (arduinoStyle) "arduino-lib-builder" else project).toByteArray().copyInto(desc, 48)
        "12:00:00".toByteArray().copyInto(desc, 80)
        "Oct 23 2026".toByteArray().copyInto(desc, 96)
        "v5.5".toByteArray().copyInto(desc, 112)
        val seg1 = desc + ByteArray(4096 - 256).also { rnd.nextBytes(it) }
        if (arduinoStyle) {
            // AVO_FW_VERSION + "AVO-CHEST" as in 3.7.1-rc2 (file offset 0x254), plus board marker
            val tag = ByteArray(1) + "$version\u0000\u0000AVO-CHEST\u0000AVOCHEST-IMG-V1:WS-AMOLED-2.06\u0000".toByteArray()
            tag.copyInto(seg1, 0x254 - 32 - 1)
        }
        val rest = maxOf(4, (approxSize - 4096 - 64) / 4 * 4)
        val seg2 = ByteArray(rest).also { rnd.nextBytes(it) }
        val out = java.io.ByteArrayOutputStream()
        val header = ByteArray(24)
        header[0] = 0xE9.toByte(); header[1] = 2; header[2] = 2; header[3] = 0x4F
        le32(0x40378000).copyInto(header, 4)
        header[8] = 0xEE.toByte()
        header[12] = 9; header[13] = 0
        header[15] = 0; header[16] = 0          // min chip rev v0.0
        header[17] = 99; header[18] = 0         // max chip rev v0.99
        header[23] = 1                          // hash appended
        out.write(header)
        var xor = 0xEF
        for ((addr, seg) in listOf(0x3C000020L to seg1, 0x42000020L to seg2)) {
            out.write(le32(addr)); out.write(le32(seg.size.toLong())); out.write(seg)
            seg.forEach { xor = xor xor (it.toInt() and 255) }
        }
        val pos = out.size()
        repeat(15 - pos % 16) { out.write(0) }
        out.write(xor)
        val body = out.toByteArray()
        return body + MessageDigest.getInstance("SHA-256").digest(body)
    }

    fun partitionTable(rows: List<PartitionTable.Entry>, withMd5: Boolean): ByteArray {
        val bytes = ByteArray(0xC00) { 0xFF.toByte() }
        rows.forEachIndexed { i, r ->
            val p = i * 32
            bytes[p] = 0xAA.toByte(); bytes[p + 1] = 0x50
            bytes[p + 2] = r.type.toByte(); bytes[p + 3] = r.subtype.toByte()
            le32(r.offset).copyInto(bytes, p + 4); le32(r.size).copyInto(bytes, p + 8)
            val label = ByteArray(16); r.name.toByteArray().copyInto(label); label.copyInto(bytes, p + 12)
            le32(r.flags).copyInto(bytes, p + 28)
        }
        if (withMd5) {
            val p = rows.size * 32
            bytes[p] = 0xEB.toByte(); bytes[p + 1] = 0xEB.toByte()
            MessageDigest.getInstance("MD5").digest(bytes.copyOfRange(0, p)).copyInto(bytes, p + 16)
        }
        return bytes
    }

    val historical = listOf(
        PartitionTable.Entry("nvs", 1, 2, 0x9000, 0x5000, 0),
        PartitionTable.Entry("otadata", 1, 0, 0xE000, 0x2000, 0),
        PartitionTable.Entry("app0", 0, 0x10, 0x10000, 0x600000, 0),
        PartitionTable.Entry("app1", 0, 0x11, 0x610000, 0x600000, 0),
        PartitionTable.Entry("blackbox", 1, 0x40, 0xC10000, 0x40000, 0),
        PartitionTable.Entry("coredump", 1, 3, 0xC50000, 0x10000, 0)
    )

    /** A watch in ROM mode running [version] from app0, NVS and blackbox filled with user data. */
    fun watch(version: String = "3.6.0", activeSlot: Int = 0): FakeEsp32S3 = FakeEsp32S3().apply {
        writeBootloader()
        writePartitionTable(historical)
        val old = build(version, seed = 7)
        writeImage(if (activeSlot == 0) 0x10000 else 0x610000, old)
        setOtadata(activeSlot, (activeSlot + 1).toLong(), OtaData.STATE_VALID)
        java.util.Random(3).nextBytes(ByteArray(0x5000).also { it.copyInto(flash, 0x9000) })
        java.util.Random(4).nextBytes(ByteArray(0x40000).also { it.copyInto(flash, 0xC10000) })
    }
}
