package org.avoperformance.horse.update

import java.io.OutputStream
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * READ-ONLY tools for any ESP32-S3 module (chest watch over USB-Serial/JTAG, back
 * module Heltec over its CP2102): device information, firmware identification,
 * partition read and full-flash backup. Nothing here writes or erases flash.
 */
internal class FlashReader(
    private val port: DevicePort,
    private val listener: Listener,
    private val cancel: AtomicBoolean = AtomicBoolean(false),
    private val clock: Clock = Clock.System,
    private val stubJson: () -> String,
) {
    interface Listener {
        fun onProgress(text: String, percent: Int?)
        fun onLog(line: String)
    }

    data class AppSlot(val partition: PartitionTable.Entry, val headerValid: Boolean, val project: String, val version: String,
                       val buildDate: String, val idf: String, val elfSha: String, val avo: String?)

    data class Info(
        val link: LinkKind, val chipId: Long, val revision: String, val mac: String,
        val jedec: Triple<Int, Int, Int>, val flashBytes: Long?, val configuredFlash: Long?,
        val secureBoot: Boolean, val flashEncryption: Boolean, val bootloaderValid: Boolean,
        val partitions: List<PartitionTable.Entry>, val apps: List<AppSlot>, val bootPartition: PartitionTable.Entry?,
        val otaStates: List<String>,
    ) {
        val macCompact get() = mac.replace(":", "").uppercase()
        fun report(): List<String> = buildList {
            add("Conexión: ${link.text}")
            add("Chip: ESP32-S3 (id $chipId) · revisión $revision")
            add("MAC: $mac")
            add("Flash: JEDEC %02X %02X %02X · %s físicos · %s configurados en el bootloader".format(jedec.first, jedec.second, jedec.third,
                flashBytes?.let { "${it shr 20} MB" } ?: "?", configuredFlash?.let { "${it shr 20} MB" } ?: "?"))
            add("Seguridad: Secure Boot ${if (secureBoot) "ACTIVO" else "no"} · Flash Encryption ${if (flashEncryption) "ACTIVO (la copia saldrá cifrada)" else "no"}")
            add("Bootloader: ${if (bootloaderValid) "válido" else "NO válido"}")
            if (partitions.isEmpty()) add("Tabla de particiones: no encontrada en 0x8000")
            else {
                add("Particiones:")
                partitions.forEach { add("  %-12s %s  0x%06X  %5d KB".format(it.name, typeName(it), it.offset, it.size / 1024)) }
            }
            otaStates.forEach { add(it) }
            add("Arranca: " + (bootPartition?.name ?: "—"))
            apps.forEach { a ->
                add("${a.partition.name}${if (a.partition == bootPartition) " ▶" else ""}: " + if (!a.headerValid) "sin imagen" else
                    listOfNotNull(a.avo, a.project.ifBlank { null }, a.version.ifBlank { null }).joinToString(" · "))
                if (a.headerValid) {
                    if (a.buildDate.isNotBlank()) add("    compilado: ${a.buildDate}")
                    if (a.idf.isNotBlank()) add("    ESP-IDF: ${a.idf}")
                    if (a.elfSha.isNotBlank()) add("    ELF SHA-256: ${a.elfSha}")
                }
            }
        }
        companion object {
            fun typeName(e: PartitionTable.Entry) = when (e.type) {
                0 -> when (e.subtype) { 0x00 -> "app factory"; in 0x10..0x1F -> "app ota_${e.subtype - 0x10}"; 0x20 -> "app test"; else -> "app 0x%02X".format(e.subtype) }
                1 -> when (e.subtype) { 0x00 -> "data otadata"; 0x01 -> "data phy"; 0x02 -> "data nvs"; 0x03 -> "data coredump"; 0x04 -> "data nvs_keys"
                    0x81 -> "data fat"; 0x82 -> "data spiffs"; 0x83 -> "data littlefs"; else -> "data 0x%02X".format(e.subtype) }
                else -> "tipo 0x%02X/0x%02X".format(e.type, e.subtype)
            }
        }
    }

    class Session(val link: RomLink, val rom: EspRom, val info: Info, var stub: StubFlasher? = null)

    private fun log(s: String) = listener.onLog(s)
    private fun cancelled() = cancel.get()

    /** Connects (resetting into the ROM by DTR/RTS if allowed) and identifies the module. ROM only. */
    fun connect(autoBootloader: Boolean): Session {
        var link = port.open(5_000)
        var rom = EspRom(link, clock, ::cancelled)
        listener.onProgress("Conectando con el bootloader…", null)
        log("USB: ${link.kind.text}")
        if (link.kind.isUart) link.setBaud(115200)
        val synced = runCatching { rom.sync(4) }.isSuccess
        if (!synced) {
            if (!autoBootloader) { link.close(); fail(Failure.NO_BOOTLOADER, manualHint(link.kind)) }
            if (link.kind.isUart) {
                log("Reinicio en modo descarga (DTR/RTS del puente USB-UART)…")
                LineControl(link, clock).classicResetIntoBootloader()
                clock.sleep(200)
            } else {
                log("Reinicio en modo descarga (USB-Serial/JTAG)…")
                LineControl(link, clock).resetIntoBootloader()
                link.close(); clock.sleep(600)
                link = port.open(15_000)
            }
            rom = EspRom(link, clock, ::cancelled)
            try { rom.sync(12) } catch (e: UpdateException) { link.close(); fail(Failure.NO_BOOTLOADER, manualHint(link.kind)) }
        }
        log("ROM sincronizado.")
        return try { Session(link, rom, identify(link, rom)) } catch (e: Exception) { link.close(); throw e }
    }

    private fun manualHint(kind: LinkKind) = if (kind.isUart)
        "no entra en modo descarga. Mantén PRG/BOOT, pulsa y suelta RST, suelta PRG y vuelve a intentarlo"
        else "no entra en modo descarga. Mantén BOOT, pulsa y suelta RESET, suelta BOOT y vuelve a intentarlo"

    private fun identify(link: RomLink, rom: EspRom): Info {
        listener.onProgress("Leyendo información del chip…", null)
        val sec = rom.securityInfo()
        if (sec.secureDownload) fail(Failure.UNSAFE, "modo Secure Download: el chip no permite leer la flash")
        if (sec.chipId != AppImage.CHIP_ID_ESP32S3.toLong()) fail(Failure.INCOMPATIBLE, "el chip no es un ESP32-S3 (id ${sec.chipId})")
        val m0 = rom.readReg(EspRom.EFUSE_BLOCK1_ADDR); val m1 = rom.readReg(EspRom.EFUSE_BLOCK1_ADDR + 4)
        val macBytes = byteArrayOf((m1 ushr 8).toByte(), m1.toByte(), (m0 ushr 24).toByte(), (m0 ushr 16).toByte(), (m0 ushr 8).toByte(), m0.toByte())
        val mac = macBytes.joinToString(":") { "%02X".format(it.toInt() and 255) }
        val cryptCnt = ((rom.readReg(EspRom.EFUSE_SPI_BOOT_CRYPT_CNT_REG) ushr 18) and 7L).toInt()
        val encryption = Integer.bitCount(cryptCnt) % 2 == 1
        val secureBoot = sec.secureBoot || rom.readReg(EspRom.EFUSE_SECURE_BOOT_EN_REG) and (1L shl 20) != 0L
        val rev = DeviceProbe.chipRevision(rom)
        val setup = DeviceProbe.prepare(rom)
        val boot = rom.readFlashVerified(0, 32)
        val bootValid = AppImage.headerLooksValid(boot)
        val configured = if (bootValid) AppImage.flashSizeBytes((boot[3].toInt() and 0xF0) ushr 4) else null
        listener.onProgress("Leyendo particiones…", null)
        val parts = runCatching {
            PartitionTable.parse(DeviceProbe.readPartitionTable(rom), minOf(setup.physical ?: FlashCommands.MAX_FLASH, FlashCommands.MAX_FLASH)).entries
        }.onFailure { log("Tabla de particiones: ${(it as? UpdateException)?.message ?: it.message}") }.getOrDefault(emptyList())
        val apps = parts.filter { it.type == 0 }
        val slots = apps.map { p ->
            listener.onProgress("Leyendo ${p.name}…", null)
            val head = rom.readFlashVerified(p.offset, DeviceProbe.SLOT_HEAD_BYTES)
            slotOf(p, head)
        }
        var bootPart: PartitionTable.Entry? = apps.firstOrNull { it.subtype == 0 } ?: apps.firstOrNull()
        val otaLines = ArrayList<String>()
        parts.firstOrNull { it.type == 1 && it.subtype == 0 }?.let { otaPart ->
            runCatching {
                val entries = listOf(0, 1).map { OtaData.Entry(rom.readFlashVerified(otaPart.offset + it * OtaData.SECTOR, OtaData.ENTRY_SIZE)) }
                entries.forEachIndexed { i, e -> otaLines += "otadata[$i]: " + if (e.seq == 0xFFFF_FFFFL) "vacío" else "seq ${e.seq}, ${e.stateName}, CRC ${if (e.crcOk) "ok" else "mal"}" }
                val ota = apps.filter { it.isOtaApp }.sortedBy { it.subtype }
                OtaData.bootSlot(entries, ota.size)?.let { idx -> ota.getOrNull(idx)?.let { bootPart = it } }
            }
        }
        return Info(link.kind, sec.chipId, "v%d.%d".format(rev / 100, rev % 100), mac, setup.jedec, setup.physical, configured,
            secureBoot, encryption, bootValid, parts, slots, bootPart, otaLines)
    }

    private fun slotOf(p: PartitionTable.Entry, head: ByteArray): AppSlot {
        val ok = AppImage.headerLooksValid(head)
        val d = 32
        val hasDesc = ok && head.size >= d + 256 && u32le(head, d) == AppImage.APP_DESC_MAGIC
        fun cs(o: Int, n: Int) = if (!hasDesc) "" else String(head, d + o, n, Charsets.US_ASCII).substringBefore('\u0000').filter { it.code in 32..126 }
        return AppSlot(p, ok, cs(48, 32), cs(16, 32), (cs(96, 16) + " " + cs(80, 16)).trim(), cs(112, 32),
            if (hasDesc) hex(head.copyOfRange(d + 144, d + 176)) else "", if (ok) AppImage.findAvoVersion(head, head.size) else null)
    }

    /** Loads the RAM flasher stub and, on a USB-UART bridge, raises the speed to [fastBaud]. */
    fun ensureStub(s: Session, fastBaud: Int = UART_FAST_BAUD): StubFlasher {
        s.stub?.let { return it }
        if (s.info.secureBoot) fail(Failure.UNSAFE, "con Secure Boot activo no se carga el programa de lectura rápida")
        listener.onProgress("Cargando el programa de lectura en la RAM del chip…", null)
        val stub = StubFlasher(s.rom, clock)
        stub.start(StubImage.parse(stubJson()))
        log("Stub de Espressif en marcha.")
        if (s.link.kind.isUart) {
            stub.changeBaud(s.link, fastBaud, 115200)
            log("Velocidad: $fastBaud baudios.")
        }
        s.rom.command(FlashCommands.SPI_ATTACH, le32(0)) // stub form: no ROM "legacy" word
        s.rom.spiSetParams(minOf(s.info.flashBytes ?: (4L shl 20), FlashCommands.MAX_FLASH))
        s.stub = stub
        return stub
    }

    /** Reads [length] bytes from [offset] into [sink] in 256 KB pieces, each checked against the chip's MD5. Returns SHA-256. */
    fun read(s: Session, offset: Long, length: Long, sink: OutputStream, label: String): String {
        val stub = ensureStub(s)
        val sha = MessageDigest.getInstance("SHA-256")
        val tee = object : OutputStream() {
            override fun write(b: Int) { sink.write(b); sha.update(b.toByte()) }
            override fun write(b: ByteArray, off: Int, len: Int) { sink.write(b, off, len); sha.update(b, off, len) }
        }
        // USB-UART bridges (CP2102) have a tiny FIFO: few blocks in flight, smaller pieces, and a retry
        // that restarts the chip and the stub if bytes are lost. Nothing reaches the file unless its MD5 matches.
        val uart = s.link.kind.isUart
        val piece = if (uart) 64L * 1024 else 256L * 1024
        val inFlight = if (uart) 2 else 64
        var done = 0L
        val t0 = clock.nowMs()
        var current = stub
        while (done < length) {
            if (cancel.get()) fail(Failure.CANCELLED, "lectura cancelada")
            val n = minOf(piece, length - done).toInt()
            var attempt = 0
            while (true) {
                val buf = java.io.ByteArrayOutputStream(n)
                try {
                    current.readFlash(offset + done, n, buf, inFlight) { got ->
                        val total = done + got
                        val secs = (clock.nowMs() - t0).coerceAtLeast(1) / 1000.0
                        listener.onProgress("$label · %,d de %,d KB · %.0f KB/s".format(total / 1024, length / 1024, total / 1024.0 / secs), (total * 100 / length).toInt())
                    }
                    buf.writeTo(tee)
                    break
                } catch (e: UpdateException) {
                    if (e.failure == Failure.CANCELLED || e.failure == Failure.DISCONNECTED || !uart || ++attempt > 4) throw e
                    log("Bloque 0x%X repetido (%s)".format(offset + done, e.message))
                    current = restartStub(s)
                }
            }
            done += n
        }
        return hex(sha.digest())
    }

    /** UART only: reset into the ROM again and reload the stub (the old one may be waiting for acknowledgements). */
    private fun restartStub(s: Session): StubFlasher {
        s.stub = null
        s.link.setBaud(115200)
        LineControl(s.link, clock).classicResetIntoBootloader()
        clock.sleep(200)
        s.rom.drain(200)
        s.rom.sync(12)
        DeviceProbe.prepare(s.rom)
        return ensureStub(s)
    }

    companion object { const val UART_FAST_BAUD = 460_800 }

    /** Back to the module's own firmware. */
    fun finish(s: Session) {
        runCatching {
            if (s.link.kind.isUart) LineControl(s.link, clock).classicHardReset()
            else { s.rom.clearForceDownloadBoot(); LineControl(s.link, clock).hardReset() }
        }
        s.link.close()
    }
}

/** Extracts what identifies a firmware build from its bytes (Arduino builds keep the real name only in strings). */
internal object FirmwareFingerprint {
    data class Result(val imageBytes: Int?, val sha256: String?, val info: AppImage.Info?, val strings: List<String>)

    /** Walks the segment table to find where the image really ends (padding after it is 0xFF). */
    fun imageLength(b: ByteArray): Int? {
        if (b.size < 24 || (b[0].toInt() and 255) != AppImage.MAGIC) return null
        val count = b[1].toInt() and 255
        if (count !in 1..16) return null
        var pos = 24
        repeat(count) {
            if (pos + 8 > b.size) return null
            val len = u32le(b, pos + 4)
            if (len <= 0 || len > b.size - pos - 8) return null
            pos += 8 + len.toInt()
        }
        var end = pos + (15 - pos % 16) + 1
        if (b[23].toInt() == 1) end += 32
        return end.takeIf { it <= b.size }
    }

    private val keywords = Regex("""(?i)avo|espalda|back|chest|pecho|cincha|girth|zed|f9p|ubx|rtcm|ntrip|esp-?now|heltec|lora|sx126|version|firmware|\.ino|\.cpp|\bv\d+\.\d+""")
    private val dateLike = Regex("""^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ \d]\d \d{4}$""")

    fun analyse(partition: ByteArray): Result {
        val len = imageLength(partition)
        val image = len?.let { partition.copyOf(it) }
        val info = image?.let { runCatching { AppImage.parse(it) }.getOrNull() }
        val found = LinkedHashSet<String>()
        var start = -1
        val limit = len ?: partition.size
        for (i in 0 until limit) {
            val c = partition[i].toInt() and 255
            if (c in 32..126) { if (start < 0) start = i }
            else {
                if (start >= 0 && i - start in 5..120) {
                    val s = String(partition, start, i - start, Charsets.US_ASCII).trim()
                    if (dateLike.matches(s) || keywords.containsMatchIn(s)) found += s
                }
                start = -1
            }
            if (found.size >= 400) break
        }
        val ranked = found.sortedByDescending { s ->
            (if (s.contains("AVO", true)) 4 else 0) + (if (dateLike.matches(s)) 3 else 0) + (if (s.endsWith(".ino") || s.endsWith(".cpp")) 3 else 0) +
                (if (Regex("""\d+\.\d+""").containsMatchIn(s)) 1 else 0)
        }
        return Result(len, image?.let { hex(MessageDigest.getInstance("SHA-256").digest(it)) }, info, ranked.take(60))
    }
}
