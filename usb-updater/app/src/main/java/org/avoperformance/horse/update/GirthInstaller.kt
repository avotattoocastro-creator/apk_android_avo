package org.avoperformance.horse.update

import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Installs the AVO GIRTH firmware (cincha, ESP32-C6) from its full image: bootloader, partition table,
 * otadata and app (see [GirthImage]). The C6's first-stage bootloader is in mask ROM, so an interrupted
 * write can always be repeated over USB. Every written region is checked with the chip's own MD5.
 * NVS is never written: the pairing with the back survives updates.
 */
internal class GirthInstaller(
    private val port: DevicePort,
    private val listener: Installer.Listener,
    private val cancel: AtomicBoolean = AtomicBoolean(false),
    private val clock: Clock = Clock.System
) {
    data class Outcome(val confirmed: Boolean, val message: String, val usbText: String)

    private fun step(s: Installer.Step, p: Int? = null, d: String = "") = listener.onStep(s, p, d)
    private fun log(l: String) = listener.onLog(l)
    private fun md5(b: ByteArray, from: Int, len: Int): String {
        val m = MessageDigest.getInstance("MD5"); m.update(b, from, len); return hex(m.digest())
    }

    fun install(g: GirthImage.Info, autoBootloader: Boolean): Outcome {
        step(Installer.Step.PREPARING)
        val session = Installer(port, listener, cancel, clock).connect(autoBootloader)
        val link = session.link
        val rom = session.rom
        try {
            step(Installer.Step.READING)
            val sec = rom.securityInfo()
            if (sec.chipId != AppImage.CHIP_ID_ESP32C6.toLong())
                fail(Failure.INCOMPATIBLE, "el chip conectado no es un ESP32-C6 (chip id ${sec.chipId}): este firmware es solo para la cincha")
            if (sec.secureDownload) fail(Failure.UNSAFE, "modo de descarga segura activo")
            if (sec.secureBoot) fail(Failure.UNSAFE, "Secure Boot activo: no se intenta eludir")
            if (sec.flashEncryption) fail(Failure.UNSAFE, "Flash Encryption activo: escribir en claro dejaría el módulo sin arrancar")
            log("Chip ESP32-C6 (id ${sec.chipId}) sin Secure Boot ni cifrado.")
            if (!link.kind.isUart) { rom.disableWatchdogsC6(); log("Vigilantes del chip desactivados durante la escritura (USB nativo).") }
            rom.spiAttach()
            rom.spiSetParams(minOf(g.flashSizeBytes, FlashCommands.MAX_FLASH))
            g.regions.forEach { log("Zona: ${it.name} 0x%X, %d bytes".format(it.offset, it.length)) }

            val total = g.writeBytes
            var done = 0L
            for (r in g.regions) {
                step(Installer.Step.ERASING, (done * 100 / total).toInt(), r.name)
                rom.flashBegin(r.offset.toLong(), r.length)
                val blocks = (r.length + FlashCommands.BLOCK - 1) / FlashCommands.BLOCK
                for (i in 0 until blocks) {
                    val block = ByteArray(FlashCommands.BLOCK) { 0xFF.toByte() }
                    val from = r.offset + i * FlashCommands.BLOCK
                    g.image.copyInto(block, 0, from, minOf(from + FlashCommands.BLOCK, r.offset + r.length))
                    try { rom.flashData(i, block) } catch (e: UpdateException) {
                        if (e.failure == Failure.CANCELLED) throw e
                        throw UpdateException(Failure.WRITE_INTERRUPTED, "${r.name}, bloque ${i + 1}/$blocks: ${e.message}. Repite la instalación por USB.", e)
                    }
                    done += minOf(FlashCommands.BLOCK, r.length - i * FlashCommands.BLOCK)
                    step(Installer.Step.WRITING, (done * 100 / total).toInt(), r.name)
                }
                step(Installer.Step.VERIFYING, null, "MD5 de ${r.name}")
                val inFlash = rom.flashMd5(r.offset.toLong(), r.length.toLong())
                val inFile = md5(g.image, r.offset, r.length)
                if (inFlash != inFile) fail(Failure.VERIFY_FAILED, "${r.name}: MD5 en flash $inFlash ≠ archivo $inFile. Repite la instalación.")
                log("${r.name} verificada (MD5 $inFlash).")
            }

            step(Installer.Step.REBOOTING)
            val uart = link.kind.isUart
            if (uart) LineControl(link, clock).classicHardReset() else { LineControl(link, clock).hardReset(); link.close() }
            log("Reinicio enviado.")
            return confirm(g, if (uart) link else null)
        } finally { link.close() }
    }

    /** Listens to the USB output for the firmware banner ("AVO-GIRTH <version> ready"). */
    private fun confirm(g: GirthImage.Info, keep: RomLink?): Outcome {
        step(Installer.Step.CONFIRMING, null, "Esperando el arranque de la cincha")
        val text = StringBuilder()
        val start = clock.nowMs()
        var link = keep ?: runCatching { port.open(15_000) }.getOrNull()
            ?: return Outcome(false, "Firmware grabado y verificado, pero la cincha no volvió a aparecer por USB.", "")
        try {
            val buf = ByteArray(1024)
            while (clock.nowMs() - start < 12_000 && !cancel.get()) {
                if (!link.isOpen) { link.close(); link = runCatching { port.open(5_000) }.getOrNull() ?: break; continue }
                val n = link.read(buf, 200)
                for (i in 0 until maxOf(n, 0)) { val c = buf[i].toInt() and 255; if (c == 10 || c == 13 || c in 32..126) text.append(c.toChar()) }
                if (text.contains("AVO-GIRTH ${g.version} ready")) break
            }
        } finally { link.close() }
        val usb = text.toString()
        val ok = usb.contains("AVO-GIRTH ${g.version} ready")
        val msg = if (ok) "Instalación completada. La cincha arrancó con AVO-GIRTH ${g.version}."
                  else "Firmware grabado y verificado. No se vio el arranque por USB: abre el monitor serie para comprobarlo."
        if (ok) step(Installer.Step.DONE, 100, msg)
        return Outcome(ok, msg, usb)
    }
}
