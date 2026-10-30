package org.avoperformance.horse.update

import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * BLOQUES B y C: programs an application image into the slot chosen by
 * [InstallPlanner], verifies what is really in flash, activates it through
 * otadata and checks the first boot. Pure Kotlin: Android supplies [DevicePort].
 *
 * Safety invariants (covered by InstallerSimulationTest):
 *  - nothing outside the target slot and ONE otadata sector is ever erased/written;
 *  - otadata is only touched after the image MD5 read from flash matches;
 *  - an interruption before activation leaves the previous firmware selected;
 *  - an interruption during activation leaves the other otadata copy intact.
 */
internal class Installer(
    private val port: DevicePort,
    private val listener: Listener,
    private val cancel: AtomicBoolean = AtomicBoolean(false),
    private val clock: Clock = Clock.System
) {
    enum class Step(val text: String) {
        PREPARING("Preparando conexión"),
        READING("Leyendo dispositivo"),
        PARTITIONS("Comprobando particiones"),
        VALIDATING("Validando firmware"),
        ERASING("Borrando destino"),
        WRITING("Escribiendo"),
        VERIFYING("Verificando"),
        ACTIVATING("Activando firmware"),
        REBOOTING("Reiniciando"),
        CONFIRMING("Comprobando arranque"),
        DONE("Instalación completada")
    }

    interface Listener {
        fun onStep(step: Step, percent: Int?, detail: String)
        fun onLog(line: String)
    }

    data class Outcome(
        val plan: InstallPlanner.Plan,
        val imageMd5: String,
        val bootCheck: OtaData.BootCheck?,
        val stableMs: Long,
        val resets: Int,
        val announced: Boolean,
        val bootConfirmed: Boolean,
        val message: String,
        val usbText: String
    )

    data class Options(
        /** Reset into ROM by USB-Serial-JTAG DTR/RTS if SYNC fails (reboots a running watch). */
        val autoBootloader: Boolean = true,
        /** After the first boot, re-enter ROM and read otadata (one extra reboot). */
        val romBootCheck: Boolean = true,
        val stableMs: Long = 15_000,
        val monitorMs: Long = 45_000,
        val reappearMs: Long = 20_000
    )

    /** While true, cancellation is deferred (otadata is being rewritten). */
    private val critical = AtomicBoolean(false)

    private fun cancelled() = cancel.get() && !critical.get()

    private fun step(s: Step, percent: Int? = null, detail: String = "") = listener.onStep(s, percent, detail)
    private fun log(line: String) = listener.onLog(line)
    private fun md5(b: ByteArray) = hex(MessageDigest.getInstance("MD5").digest(b))

    class Session(val link: RomLink, val rom: EspRom) {
        fun close() = link.close()
    }

    /** Opens the watch and synchronises with the ROM, entering download mode by USB if allowed. */
    fun connect(autoBootloader: Boolean): Session {
        var link = port.open(5_000)
        var rom = EspRom(link, clock, ::cancelled)
        try {
            rom.sync(6)
            log("ROM sincronizado (bootloader del chip).")
            return Session(link, rom)
        } catch (e: UpdateException) {
            if (e.failure != Failure.NO_BOOTLOADER || !autoBootloader) { link.close(); throw e }
        }
        if (link.kind.isUart) {
            log("Sin SYNC: reiniciando el módulo en modo descarga (DTR/RTS del puente USB-UART)…")
            LineControl(link, clock).classicResetIntoBootloader()
            clock.sleep(200)
        } else {
            log("Sin SYNC: reiniciando el reloj en modo bootloader por USB (DTR/RTS)…")
            LineControl(link, clock).resetIntoBootloader()
            link.close()
            clock.sleep(600)
            link = port.open(15_000)
        }
        rom = EspRom(link, clock, ::cancelled)
        try {
            rom.sync(12)
        } catch (e: UpdateException) {
            link.close()
            if (e.failure == Failure.NO_BOOTLOADER) fail(Failure.NO_BOOTLOADER,
                "el reloj no entró en modo bootloader. Mantén BOOT, pulsa y suelta RESET, suelta BOOT y vuelve a intentarlo")
            throw e
        }
        log("ROM sincronizado tras reinicio por USB.")
        return Session(link, rom)
    }

    /**
     * BLOQUE A only: read-only identification. With [rebootAfter] the watch is
     * sent back to its application afterwards (only used when the ROM was entered by USB).
     */
    fun probe(autoBootloader: Boolean = false, rebootAfter: Boolean = autoBootloader): DeviceProbe.Snapshot {
        step(Step.PREPARING)
        val s = connect(autoBootloader)
        try {
            step(Step.READING)
            val snap = DeviceProbe.run(s.rom, ::log)
            if (rebootAfter) {
                s.rom.clearForceDownloadBoot()
                if (s.link.kind.isUart) LineControl(s.link, clock).classicHardReset() else LineControl(s.link, clock).hardReset()
                log("Lectura terminada; el reloj vuelve a su firmware.")
            }
            return snap
        } finally { s.close() }
    }

    fun install(image: ByteArray, options: Options = Options()): Outcome {
        // ---- validate the file first: nothing is touched if it is not a valid S3 app image
        step(Step.VALIDATING, null, "Comprobando el BIN")
        val info = AppImage.parse(image)
        val imageMd5 = md5(image)
        log("Firmware: ${info.label.ifBlank { "sin descripción" }} · ${info.size} bytes · SHA-256 ${info.sha256}")

        step(Step.PREPARING)
        val session = connect(options.autoBootloader)
        val link = session.link
        val rom = session.rom
        try {
            step(Step.READING)
            val device = DeviceProbe.run(rom, ::log)
            device.report().forEach(::log)

            // chest firmware never goes to the back module and vice versa
            if (link.kind.isUart && info.avoChestMarker)
                fail(Failure.INCOMPATIBLE, "es un firmware del PECHO y el módulo conectado es la ESPALDA (puente USB-UART)")
            if (!link.kind.isUart && info.isAvoBack)
                fail(Failure.INCOMPATIBLE, "es un firmware de la ESPALDA y el dispositivo conectado es el PECHO (USB nativo)")

            step(Step.PARTITIONS)
            val plan = InstallPlanner.plan(device, info)
            plan.summary().forEach(::log)
            val target = plan.target.partition

            // ---- fingerprints of everything that must stay untouched
            val protectedRegions = protectedRegions(device, plan)
            val before = protectedRegions.associateWith { rom.flashMd5(it.offset, it.size) }
            log("Huellas MD5 de ${protectedRegions.size} zonas protegidas registradas.")

            // ---- erase + write (ROM FLASH_BEGIN erases only the sectors covering the image)
            step(Step.ERASING, 0, "${plan.eraseBytes / 1024} KB en ${target.name}")
            rom.flashBegin(target.offset, image.size)
            val blocks = (image.size + FlashCommands.BLOCK - 1) / FlashCommands.BLOCK
            var lastPercent = -1
            for (i in 0 until blocks) {
                val block = ByteArray(FlashCommands.BLOCK) { 0xFF.toByte() }
                val from = i * FlashCommands.BLOCK
                image.copyInto(block, 0, from, minOf(from + FlashCommands.BLOCK, image.size))
                try {
                    rom.flashData(i, block)
                } catch (e: UpdateException) {
                    if (e.failure == Failure.CANCELLED) throw e
                    throw UpdateException(Failure.WRITE_INTERRUPTED,
                        "bloque ${i + 1}/$blocks: ${e.message}. El firmware anterior sigue seleccionado.", e)
                }
                val percent = (i + 1) * 100 / blocks
                if (percent != lastPercent) { lastPercent = percent; step(Step.WRITING, percent, "${i + 1}/$blocks bloques") }
            }

            // ---- verify the bytes really stored in flash
            step(Step.VERIFYING, null, "MD5 calculado por el chip sobre ${target.name}")
            val written = rom.flashMd5(target.offset, image.size.toLong())
            if (written != imageMd5)
                fail(Failure.VERIFY_FAILED, "MD5 en flash $written ≠ archivo $imageMd5. No se activa; el firmware anterior sigue seleccionado.")
            val head = rom.readFlashVerified(target.offset, DeviceProbe.SLOT_HEAD_BYTES)
            if (!head.contentEquals(image.copyOf(DeviceProbe.SLOT_HEAD_BYTES)))
                fail(Failure.VERIFY_FAILED, "la cabecera leída no coincide con el archivo")
            checkUntouched(rom, before, "tras la escritura")
            log("Imagen verificada en flash: MD5 $written.")

            // ---- activation (otadata), deferred cancellation from here on
            step(Step.ACTIVATING, null, "otadata[${plan.otaUpdate.sector}] → ${plan.target.label}")
            critical.set(true)
            try {
                activate(rom, device, plan)
            } finally { critical.set(false) }
            checkUntouched(rom, before - protectedRegions.filter { it.isOtadataSector(plan.otadataSectorAddress) }.toSet(), "tras la activación")

            // ---- reboot into the application
            step(Step.REBOOTING)
            rom.clearForceDownloadBoot()
            if (link.kind.isUart) {
                LineControl(link, clock).classicHardReset()
                log("Reinicio enviado (RTS del puente USB-UART).")
                return confirm(plan, info, imageMd5, options, keep = link)   // the bridge stays on the bus
            }
            LineControl(link, clock).hardReset()
            link.close()
            log("Reinicio enviado (RTS).")

            return confirm(plan, info, imageMd5, options)
        } finally {
            link.close()
        }
    }

    // ------------------------------------------------------------------ helpers

    data class Region(val name: String, val offset: Long, val size: Long) {
        fun isOtadataSector(address: Long) = offset == address && size == OtaData.SECTOR.toLong()
    }

    private fun protectedRegions(d: DeviceProbe.Snapshot, plan: InstallPlanner.Plan): List<Region> = buildList {
        add(Region("bootloader", 0, DeviceProbe.PARTITION_TABLE_OFFSET))
        add(Region("tabla de particiones", DeviceProbe.PARTITION_TABLE_OFFSET, 0x1000))
        for (p in d.partitions.entries) {
            if (p === plan.target.partition) continue
            if (p === plan.otadataPartition) {
                add(Region("otadata[0]", p.offset, OtaData.SECTOR.toLong()))
                add(Region("otadata[1]", p.offset + OtaData.SECTOR, OtaData.SECTOR.toLong()))
                continue
            }
            // MD5 of the whole region for data partitions up to 1 MB; first 64 KB of app slots / larger data.
            val limit = if (p.type == 0) 0x10000L else 0x100000L
            add(Region(p.name, p.offset, minOf(p.size, limit)))
        }
    }

    private fun checkUntouched(rom: EspRom, before: Map<Region, String>, whenText: String) {
        for ((r, md5) in before) {
            val now = rom.flashMd5(r.offset, r.size)
            if (now != md5) fail(Failure.VERIFY_FAILED, "la zona protegida '${r.name}' cambió $whenText (no debería)")
        }
    }

    private fun activate(rom: EspRom, device: DeviceProbe.Snapshot, plan: InstallPlanner.Plan) {
        val base = plan.otadataPartition.offset
        val current = listOf(0, 1).map { OtaData.Entry(rom.readFlashVerified(base + it * OtaData.SECTOR, OtaData.ENTRY_SIZE)) }
        if (current.indices.any { !current[it].raw.contentEquals(device.otadata[it].raw) })
            fail(Failure.UNSAFE, "otadata cambió desde la lectura inicial; no se activa")
        val sectorImage = plan.otaUpdate.sectorImage()
        val address = plan.otadataSectorAddress
        rom.flashBegin(address, sectorImage.size)
        for (i in 0 until sectorImage.size / FlashCommands.BLOCK) {
            rom.flashData(i, sectorImage.copyOfRange(i * FlashCommands.BLOCK, (i + 1) * FlashCommands.BLOCK))
        }
        if (rom.flashMd5(address, sectorImage.size.toLong()) != md5(sectorImage))
            fail(Failure.VERIFY_FAILED, "otadata no se grabó correctamente. La otra copia de otadata está intacta y el bootloader la usará.")
        val after = listOf(0, 1).map { OtaData.Entry(rom.readFlashVerified(base + it * OtaData.SECTOR, OtaData.ENTRY_SIZE)) }
        val other = 1 - plan.otaUpdate.sector
        if (!after[other].raw.contentEquals(current[other].raw)) fail(Failure.VERIFY_FAILED, "la copia de otadata que no debía tocarse cambió")
        if (OtaData.bootSlot(after, 2) != plan.target.index)
            fail(Failure.VERIFY_FAILED, "otadata no selecciona ${plan.target.label} tras la activación")
        log("otadata verificado: el bootloader seleccionará ${plan.target.label} (seq ${plan.otaUpdate.seq}).")
    }

    private fun confirm(plan: InstallPlanner.Plan, info: AppImage.Info, imageMd5: String, options: Options, keep: RomLink? = null): Outcome {
        step(Step.CONFIRMING, null, "Esperando a que el reloj vuelva a aparecer por USB")
        val text = StringBuilder()
        var resets = 0
        var stableSince = -1L
        var bestStable = 0L
        val start = clock.nowMs()
        var link: RomLink? = null
        try {
            link = keep ?: runCatching { port.open(options.reappearMs) }.getOrNull()
            if (link == null) {
                return Outcome(plan, imageMd5, null, 0, 0, false, false,
                    "Firmware grabado, verificado y activado, pero el reloj no volvió a aparecer por USB. Comprueba la pantalla del reloj.", "")
            }
            stableSince = clock.nowMs()
            val buf = ByteArray(1024)
            while (clock.nowMs() - start < options.monitorMs) {
                if (cancel.get()) break
                val current = link!!
                if (!current.isOpen) {
                    resets++
                    bestStable = maxOf(bestStable, clock.nowMs() - stableSince)
                    log("El reloj se desconectó (posible reinicio #$resets).")
                    current.close()
                    link = keep ?: runCatching { port.open(options.reappearMs) }.getOrNull() ?: break
                    stableSince = clock.nowMs()
                    continue
                }
                val n = current.read(buf, 200)
                if (n > 0) for (i in 0 until n) {
                    val c = buf[i].toInt() and 255
                    if (c == 10 || c == 13 || c in 32..126) text.append(c.toChar())
                }
                if (text.length > 4000) text.delete(0, text.length - 4000)
                if (clock.nowMs() - stableSince >= options.stableMs && resets == 0) break
            }
            if (stableSince >= 0 && link?.isOpen == true) bestStable = maxOf(bestStable, clock.nowMs() - stableSince)
            val usb = text.toString()
            val announced = info.runtimeVersion.isNotBlank() && usb.contains(info.runtimeVersion)
            if (announced) log("El firmware se anunció por USB con la versión ${info.runtimeVersion}.")
            if (resets >= 3) {
                return Outcome(plan, imageMd5, null, bestStable, resets, announced, false,
                    "El reloj se reinicia repetidamente ($resets veces): el firmware no arranca de forma estable.", usb)
            }

            var check: OtaData.BootCheck? = null
            if (options.romBootCheck && link!!.isOpen) {
                step(Step.CONFIRMING, null, "Leyendo otadata tras el primer arranque")
                val appLink = link!!
                link = null // closed inside romBootCheck
                check = try { romBootCheck(appLink, plan) } catch (e: UpdateException) {
                    if (e.failure == Failure.CANCELLED) throw e
                    log("No se pudo releer otadata tras el arranque: ${e.message}"); null
                }
                check?.let { log("Comprobación de arranque: ${it.text}") }
            }
            val confirmed = check == OtaData.BootCheck.CONFIRMED ||
                (announced && check != OtaData.BootCheck.ROLLED_BACK && check != OtaData.BootCheck.NOT_SELECTED &&
                    check != OtaData.BootCheck.RUNNING_UNCONFIRMED)
            val message = when {
                confirmed -> "Instalación completada. Arranque confirmado" +
                    (if (check == OtaData.BootCheck.CONFIRMED) " por el bootloader (VALID)." else " por la salida USB del firmware.")
                check?.confirmed == false -> "El firmware quedó grabado y activado, pero no arrancó correctamente: ${check.text}"
                check == OtaData.BootCheck.RUNNING_UNCONFIRMED -> "Grabado y activado. ${check.text} En el próximo reinicio el bootloader volverá al firmware anterior si la aplicación no lo confirma."
                else -> "Grabado, verificado y activado. Arranque NO confirmado automáticamente" +
                    (check?.let { ": ${it.text}" } ?: ".") + " Comprueba la versión en la pantalla del reloj."
            }
            if (confirmed) step(Step.DONE, 100, message)
            return Outcome(plan, imageMd5, check, bestStable, resets, announced, confirmed, message, usb)
        } finally {
            link?.close()
        }
    }

    /** Re-enters ROM through USB-Serial-JTAG, reads otadata and boots the app again. */
    private fun romBootCheck(appLink: RomLink, plan: InstallPlanner.Plan): OtaData.BootCheck {
        val uart = appLink.kind.isUart
        val link: RomLink
        if (uart) {
            LineControl(appLink, clock).classicResetIntoBootloader()
            clock.sleep(200)
            link = appLink
        } else {
            LineControl(appLink, clock).resetIntoBootloader()
            appLink.close()
            clock.sleep(600)
            link = port.open(15_000)
        }
        fun runApp() = if (uart) LineControl(link, clock).classicHardReset() else LineControl(link, clock).hardReset()
        try {
            val rom = EspRom(link, clock) { false }
            rom.sync(12)
            DeviceProbe.prepare(rom)
            val base = plan.otadataPartition.offset
            val entries = listOf(0, 1).map { OtaData.Entry(rom.readFlashVerified(base + it * OtaData.SECTOR, OtaData.ENTRY_SIZE)) }
            val result = OtaData.checkAfterBoot(entries, plan.target.index, 2, plan.otaUpdate.seq)
            rom.clearForceDownloadBoot()
            runApp()
            return result
        } catch (e: UpdateException) {
            runCatching { runApp() }
            throw e
        } finally {
            link.close()
        }
    }
}
