package org.avoperformance.horse.update

import java.io.OutputStream
import java.security.MessageDigest
import java.util.Base64

/**
 * Espressif esp-flasher-stub v1.4.1 for ESP32-S3 (Apache-2.0 OR MIT, bundled as
 * assets/stub/esp32s3.json exactly as shipped by esptool). It runs in the chip's RAM
 * and streams flash much faster than the ROM. Only its READ_FLASH, SPI_ATTACH,
 * SPI_SET_PARAMS, CHANGE_BAUDRATE and READ_REG commands are used: this code never
 * writes or erases flash.
 */
internal class StubImage(val text: ByteArray, val textStart: Long, val data: ByteArray?, val dataStart: Long?, val entry: Long) {
    companion object {
        /** Reads the top-level fields of the esptool stub JSON (nested plugin objects are skipped). */
        fun parse(json: String): StubImage {
            val top = HashMap<String, String>()
            var depth = 0; var i = 0; var key: String? = null; var expectValue = false
            while (i < json.length) {
                val c = json[i]
                when {
                    c == '{' || c == '[' -> { depth++; if (depth > 1) key = null; i++ }
                    c == '}' || c == ']' -> { depth--; i++ }
                    c == '"' -> {
                        val end = json.indexOf('"', i + 1)
                        val str = json.substring(i + 1, end)
                        if (depth == 1) { if (expectValue && key != null) { top[key!!] = str; key = null; expectValue = false } else key = str }
                        i = end + 1
                    }
                    c == ':' -> { expectValue = true; i++ }
                    c == ',' -> { expectValue = false; if (depth == 1) key = null; i++ }
                    c.isDigit() || c == '-' -> {
                        var e = i; while (e < json.length && (json[e].isDigit() || json[e] == '-')) e++
                        if (depth == 1 && expectValue && key != null) { top[key!!] = json.substring(i, e); key = null; expectValue = false }
                        i = e
                    }
                    else -> i++
                }
            }
            fun num(k: String) = top[k]?.toLong() ?: error("stub sin campo $k")
            val dec = Base64.getDecoder()
            return StubImage(
                dec.decode(top["text"] ?: error("stub sin text")), num("text_start"),
                top["data"]?.let { dec.decode(it) }, top["data_start"]?.toLong(), num("entry"),
            )
        }
    }
}

internal class StubFlasher(private val rom: EspRom, private val clock: Clock = Clock.System) {
    companion object {
        const val MEM_BEGIN = 0x05
        const val MEM_END = 0x06
        const val MEM_DATA = 0x07
        const val CHANGE_BAUDRATE = 0x0F
        const val READ_FLASH = 0xD2
        const val RAM_BLOCK = 0x1800
        const val SECTOR = 0x1000
    }

    private fun upload(data: ByteArray, address: Long) {
        val blocks = (data.size + RAM_BLOCK - 1) / RAM_BLOCK
        rom.command(MEM_BEGIN, le32(data.size.toLong()) + le32(blocks.toLong()) + le32(RAM_BLOCK.toLong()) + le32(address))
        for (seq in 0 until blocks) {
            val block = data.copyOfRange(seq * RAM_BLOCK, minOf(data.size, (seq + 1) * RAM_BLOCK))
            rom.command(MEM_DATA, le32(block.size.toLong()) + le32(seq.toLong()) + le32(0) + le32(0) + block,
                FlashCommands.checksum(block), attempts = 2)
        }
    }

    /** Uploads and starts the stub; waits for its "OHAI" greeting. */
    fun start(stub: StubImage) {
        upload(stub.text, stub.textStart)
        if (stub.data != null && stub.dataStart != null) upload(stub.data, stub.dataStart)
        rom.sendOnly(MEM_END, le32(0) + le32(stub.entry))
        val deadline = clock.nowMs() + 3000
        while (clock.nowMs() < deadline) {
            val f = rom.rawFrame(deadline - clock.nowMs()) ?: break
            if (f.contentEquals("OHAI".toByteArray())) return
            // the MEM_END reply (if the ROM sends it) is skipped
        }
        fail(Failure.NO_BOOTLOADER, "el programa de lectura (stub) no arrancó")
    }

    /** CHANGE_BAUDRATE through the stub (it takes the new and the current rate). */
    fun changeBaud(link: RomLink, newBaud: Int, oldBaud: Int) {
        rom.command(CHANGE_BAUDRATE, le32(newBaud.toLong()) + le32(oldBaud.toLong()))
        link.setBaud(newBaud)
        clock.sleep(60)
        rom.drain(60)
    }

    /**
     * esptool read_flash with the stub: data arrives in 4 KB SLIP frames, each one
     * acknowledged with the running byte count; the stub ends with the MD5 of the
     * region, which is checked before anything is reported as read.
     */
    fun readFlash(offset: Long, length: Int, sink: OutputStream, inFlight: Int = 64, progress: (Int) -> Unit = {}): String {
        rom.command(READ_FLASH, le32(offset) + le32(length.toLong()) + le32(SECTOR.toLong()) + le32(inFlight.toLong()), timeoutMs = 5000)
        val md5 = MessageDigest.getInstance("MD5")
        var got = 0
        while (got < length) {
            val p = rom.rawFrame(5000) ?: fail(Failure.VERIFY_FAILED, "lectura interrumpida en 0x%X".format(offset + got))
            if (rom.replyOf(p, READ_FLASH) != null) continue
            if (got + p.size < length && p.size != SECTOR) fail(Failure.VERIFY_FAILED, "bloque de ${p.size} bytes en 0x%X".format(offset + got))
            if (got + p.size > length) fail(Failure.VERIFY_FAILED, "el stub envió más datos de los pedidos")
            sink.write(p); md5.update(p)
            got += p.size
            rom.writeFrame(le32(got.toLong()))
            progress(got)
        }
        val digest = rom.rawFrame(5000) ?: fail(Failure.VERIFY_FAILED, "falta el MD5 de la lectura")
        if (digest.size != 16) fail(Failure.VERIFY_FAILED, "MD5 con formato desconocido")
        val mine = md5.digest()
        if (!mine.contentEquals(digest)) fail(Failure.VERIFY_FAILED, "MD5 distinto en 0x%X: los datos no se guardan".format(offset))
        return hex(mine)
    }
}
