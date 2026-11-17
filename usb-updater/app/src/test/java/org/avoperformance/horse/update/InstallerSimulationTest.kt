package org.avoperformance.horse.update

import org.junit.Assert.*
import org.junit.Test
import java.security.MessageDigest

/**
 * END-TO-END SIMULATION of the USB installer against [FakeEsp32S3].
 * These are simulation results; they do not replace the physical test with the watch.
 */
class InstallerSimulationTest {
    private val newImage = TestImages.build("3.7.1-rc2", "AVO-CHEST", 400_000, seed = 11, arduinoStyle = true)

    private class Recorder : Installer.Listener {
        val steps = mutableListOf<Installer.Step>()
        val log = mutableListOf<String>()
        override fun onStep(step: Installer.Step, percent: Int?, detail: String) {
            if (steps.lastOrNull() != step) steps.add(step)
        }
        override fun onLog(line: String) { log.add(line) }
    }

    private fun installer(fake: FakeEsp32S3, rec: Recorder = Recorder()) =
        Installer(fake.port, rec, clock = fake.clock)

    private fun md5(b: ByteArray) = hex(MessageDigest.getInstance("MD5").digest(b))

    private fun snapshotProtected(fake: FakeEsp32S3) = mapOf(
        "boot+table" to md5(fake.region(0, 0x9000)),
        "nvs" to md5(fake.region(0x9000, 0x5000)),
        "blackbox" to md5(fake.region(0xC10000, 0x40000)),
        "coredump" to md5(fake.region(0xC50000, 0x10000))
    )

    private fun assertOnlyAllowedWrites(fake: FakeEsp32S3, slotOffset: Long, otadataSector: Long) {
        for (r in fake.erasedRegions + fake.writeRanges) {
            val inSlot = r.first >= slotOffset && r.last < slotOffset + 0x600000
            val inOtadata = r.first >= otadataSector && r.last < otadataSector + 0x1000
            assertTrue("escritura fuera de lo permitido: 0x%X-0x%X".format(r.first, r.last), inSlot || inOtadata)
        }
    }

    @Test fun normalUpdateWritesInactiveSlotActivatesAndConfirmsBoot() {
        val fake = TestImages.watch("3.6.0", activeSlot = 0)
        val before = snapshotProtected(fake)
        val oldApp = fake.region(0x10000, 0x10000)
        val rec = Recorder()
        val out = installer(fake, rec).install(newImage)

        assertEquals(InstallPlanner.Mode.NORMAL, out.plan.mode)
        assertEquals("app1", out.plan.target.partition.name)
        assertArrayEquals(newImage, fake.region(0x610000, newImage.size))
        assertArrayEquals("el slot activo anterior no se toca", oldApp, fake.region(0x10000, 0x10000))
        assertEquals(before, snapshotProtected(fake))
        assertOnlyAllowedWrites(fake, 0x610000, 0xF000)
        assertEquals(20, fake.lastFlashBeginPayloadSize)
        assertTrue(fake.watchdogsDisabled || fake.boots > 0)
        assertEquals(1, fake.bootedSlot)
        assertEquals(OtaData.BootCheck.CONFIRMED, out.bootCheck)
        assertTrue(out.message, out.bootConfirmed)
        assertTrue(out.announced)
        assertEquals(Installer.Step.DONE, rec.steps.last())
        assertTrue(rec.steps.containsAll(listOf(Installer.Step.ERASING, Installer.Step.WRITING,
            Installer.Step.VERIFYING, Installer.Step.ACTIVATING, Installer.Step.REBOOTING)))
    }

    @Test fun secondUpdateGoesBackToFirstSlot() {
        val fake = TestImages.watch("3.6.0", activeSlot = 1)
        val out = installer(fake).install(newImage)
        assertEquals("app0", out.plan.target.partition.name)
        assertEquals(0, fake.bootedSlot)
        assertTrue(out.bootConfirmed)
    }

    @Test fun recoveryRewritesBrokenSelectedSlot() {
        val fake = TestImages.watch("3.6.0", activeSlot = 0)
        // app0 selected by otadata but damaged; app1 empty -> watch does not boot
        for (i in 0x10000 until 0x10100) fake.flash[i] = 0
        val out = installer(fake).install(newImage)
        assertEquals(InstallPlanner.Mode.RECOVERY, out.plan.mode)
        assertEquals("app0", out.plan.target.partition.name)
        assertEquals(0, fake.bootedSlot)
        assertTrue(out.bootConfirmed)
    }

    @Test fun recoveryFromEmptyOtadata() {
        val fake = TestImages.watch("3.6.0", activeSlot = 0)
        for (i in 0xE000 until 0x10000) fake.flash[i] = 0xFF.toByte()
        for (i in 0x10000 until 0x10100) fake.flash[i] = 0
        val out = installer(fake).install(newImage)
        assertEquals(InstallPlanner.Mode.RECOVERY, out.plan.mode)
        assertEquals("app0", out.plan.target.partition.name)
        assertTrue(out.bootConfirmed)
    }

    @Test fun watchRunningAppIsResetIntoBootloaderByUsb() {
        val fake = TestImages.watch().apply { chipReset(FakeEsp32S3.Mode.APP) }
        fake.clock.sleep(2000)
        val out = installer(fake).install(newImage)
        assertTrue(out.bootConfirmed)
    }

    @Test fun disconnectDuringWriteKeepsPreviousFirmwareSelected() {
        val fake = TestImages.watch("3.6.0", activeSlot = 0).apply { disconnectAfterDataBlocks = 100 }
        val otadataBefore = fake.region(0xE000, 0x2000)
        val e = assertThrows(UpdateException::class.java) { installer(fake).install(newImage) }
        assertTrue(e.failure == Failure.WRITE_INTERRUPTED || e.failure == Failure.DISCONNECTED)
        assertArrayEquals("otadata intacto", otadataBefore, fake.region(0xE000, 0x2000))
        // power back: the old firmware still boots, and a retry succeeds
        fake.disconnectAfterDataBlocks = -1
        fake.chipReset(FakeEsp32S3.Mode.APP)
        assertEquals(0, fake.bootedSlot)
        fake.dataBlocks = 0
        assertTrue(installer(fake).install(newImage).bootConfirmed)
    }

    @Test fun verificationFailureBlocksActivation() {
        val fake = TestImages.watch().apply { }
        val otadataBefore = fake.region(0xE000, 0x2000)
        // corrupt the MD5 answer right after the data blocks: arm it when writing starts
        val rec = object : Installer.Listener {
            override fun onStep(step: Installer.Step, percent: Int?, detail: String) {
                if (step == Installer.Step.VERIFYING) fake.corruptMd5Once = true
            }
            override fun onLog(line: String) {}
        }
        val e = assertThrows(UpdateException::class.java) { Installer(fake.port, rec, clock = fake.clock).install(newImage) }
        assertEquals(Failure.VERIFY_FAILED, e.failure)
        assertArrayEquals(otadataBefore, fake.region(0xE000, 0x2000))
    }

    @Test fun crashingFirmwareIsDetectedAndRolledBack() {
        val fake = TestImages.watch("3.6.0").apply { appHealthy = { it != "3.7.1-rc2" } }
        val out = installer(fake).install(newImage)
        assertFalse(out.bootConfirmed)
        assertEquals(0, fake.bootedSlot) // bootloader rollback to the previous image
    }

    @Test fun unconfirmedFirmwareIsNotReportedAsInstalled() {
        val fake = TestImages.watch().apply { appConfirms = false; appPrintsVersion = false }
        val out = installer(fake).install(newImage)
        assertFalse(out.bootConfirmed)
        assertEquals(OtaData.BootCheck.RUNNING_UNCONFIRMED, out.bootCheck)
    }

    @Test fun secureBootBlocksBeforeAnyWrite() {
        val fake = TestImages.watch().apply { securityFlags = 1; efuseSecureBoot = true }
        val e = assertThrows(UpdateException::class.java) { installer(fake).install(newImage) }
        assertEquals(Failure.UNSAFE, e.failure)
        assertTrue(fake.erasedRegions.isEmpty() && fake.writeRanges.isEmpty())
    }

    @Test fun flashEncryptionBlocksBeforeAnyWrite() {
        val fake = TestImages.watch().apply { cryptCnt = 1; efuseCryptCnt = 1 }
        assertEquals(Failure.UNSAFE, assertThrows(UpdateException::class.java) { installer(fake).install(newImage) }.failure)
        assertTrue(fake.erasedRegions.isEmpty())
    }

    @Test fun corruptPartitionTableBlocks() {
        val fake = TestImages.watch()
        fake.flash[0x8000 + 40] = 0x77 // breaks the MD5 row
        val e = assertThrows(UpdateException::class.java) { installer(fake).install(newImage) }
        assertEquals(Failure.PARTITION, e.failure)
        assertTrue(fake.erasedRegions.isEmpty())
    }

    @Test fun firmwareTooLargeForSlotBlocks() {
        val fake = FakeEsp32S3().apply {
            writeBootloader()
            writePartitionTable(listOf(
                PartitionTable.Entry("nvs", 1, 2, 0x9000, 0x5000, 0),
                PartitionTable.Entry("otadata", 1, 0, 0xE000, 0x2000, 0),
                PartitionTable.Entry("app0", 0, 0x10, 0x10000, 0x40000, 0),
                PartitionTable.Entry("app1", 0, 0x11, 0x50000, 0x40000, 0)))
            writeImage(0x10000, TestImages.build("1.0", approxSize = 100_000))
            setOtadata(0, 1, OtaData.STATE_VALID)
        }
        val e = assertThrows(UpdateException::class.java) { installer(fake).install(newImage) }
        assertEquals(Failure.INCOMPATIBLE, e.failure)
        assertTrue(fake.erasedRegions.isEmpty())
    }

    @Test fun invalidBinNeverTouchesTheWatch() {
        val fake = TestImages.watch()
        val bad = newImage.copyOf().also { it[1000] = (it[1000] + 1).toByte() }
        assertThrows(UpdateException::class.java) { installer(fake).install(bad) }
        assertEquals(0, fake.dataBlocks)
    }

    @Test fun probeReadsRealDeviceState() {
        val fake = TestImages.watch("3.6.0", activeSlot = 0)
        val snap = installer(fake).probe()
        assertEquals(6, snap.partitions.entries.size)
        assertTrue(snap.partitions.hasMd5Record)
        assertEquals(32L shl 20, snap.physicalFlash)
        assertEquals(16L shl 20, snap.configuredFlash)
        assertEquals(0, snap.bootSlot)
        assertEquals("AVO-CHEST 3.6.0", snap.slots[0].description)
        assertFalse(snap.slots[1].headerValid)
        assertEquals(2, snap.chipRevisionFull)
        assertTrue(snap.report().joinToString("\n").contains("app1"))
    }

    @Test fun cancellationBeforeActivationLeavesWatchBootable() {
        val fake = TestImages.watch()
        val cancel = java.util.concurrent.atomic.AtomicBoolean(false)
        val rec = object : Installer.Listener {
            override fun onStep(step: Installer.Step, percent: Int?, detail: String) {
                if (step == Installer.Step.WRITING && (percent ?: 0) >= 30) cancel.set(true)
            }
            override fun onLog(line: String) {}
        }
        val e = assertThrows(UpdateException::class.java) { Installer(fake.port, rec, cancel, fake.clock).install(newImage) }
        assertEquals(Failure.CANCELLED, e.failure)
        fake.chipReset(FakeEsp32S3.Mode.APP)
        assertEquals(0, fake.bootedSlot)
    }

    @Test fun backFirmwareIsIdentifiedAndRefusedOnTheChest() {
        val back = TestImages.build("3.8.0", approxSize = 300_000, seed = 21, arduinoStyle = true, backMarker = true)
        val info = AppImage.parse(back)
        assertEquals("3.8.0", info.avoBackVersion)
        assertEquals("AVO-BACK 3.8.0", info.label)
        val fake = TestImages.watch()
        val before = fake.flash.copyOf()
        val e = assertThrows(UpdateException::class.java) { installer(fake).install(back) }
        assertEquals(Failure.INCOMPATIBLE, e.failure)
        assertArrayEquals("nada escrito", before, fake.flash)
    }
}
