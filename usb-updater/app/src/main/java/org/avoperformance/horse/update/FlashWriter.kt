package org.avoperformance.horse.update

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.os.SystemClock
import java.security.MessageDigest

/**
 * ROM flasher for an already verified INACTIVE OTA slot. Does not switch boot.
 * Never invoke without a plan derived from live, authenticated device data.
 */
internal class FlashWriter(
    private val usb: UsbDeviceConnection,
    private val out: UsbEndpoint,
    private val input: UsbEndpoint
) {
    private fun exchange(opcode: Int, frame: ByteArray, timeoutMs: Long): RomProtocol.Reply {
        check(usb.bulkTransfer(out, frame, frame.size, 3000) == frame.size) {
            "USB: transmisión incompleta, opcode $opcode"
        }
        val received = ArrayList<Byte>(512)
        val until = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < until && received.size < 8192) {
            val chunk = ByteArray(512)
            val n = usb.bulkTransfer(input, chunk, chunk.size, 300)
            if (n <= 0) continue
            received.addAll(chunk.take(n))
            val reply = RomProtocol.decodeFrames(received.toByteArray())
                .mapNotNull(RomProtocol::parseReply).firstOrNull { it.opcode == opcode }
            if (reply != null) {
                // ESP ROM appends two status bytes on command acknowledgements.
                if (opcode != FlashCommands.FLASH_MD5) {
                    check(reply.payload.size >= 2 && reply.payload.takeLast(2).all { it == 0.toByte() }) {
                        "ROM rechazó opcode $opcode"
                    }
                }
                return reply
            }
        }
        error("ROM no respondió al opcode $opcode")
    }

    fun writeInactive(
        image: ByteArray,
        plan: OtaPlan.Plan,
        progress: (Int, Int) -> Unit
    ): String {
        require(image.isNotEmpty() && image.size.toLong() <= plan.target.size)
        require(plan.active.offset != plan.target.offset)
        ImageSegments.validate(image)
        val blocks = (image.size + FlashCommands.BLOCK - 1) / FlashCommands.BLOCK
        exchange(FlashCommands.FLASH_BEGIN,
            FlashCommands.begin(plan.target.offset, image.size), 60000L)
        for (i in 0 until blocks) {
            val offset = i * FlashCommands.BLOCK
            val block = ByteArray(FlashCommands.BLOCK) { 0xFF.toByte() }
            image.copyInto(block, 0, offset, minOf(offset + block.size, image.size))
            exchange(FlashCommands.FLASH_DATA, FlashCommands.data(i, block), 6000L)
            progress(i + 1, blocks)
        }
        val md5 = exchange(FlashCommands.FLASH_MD5,
            FlashCommands.md5(plan.target.offset, image.size.toLong()), 15000L)
        val expected = MessageDigest.getInstance("MD5").digest(image)
        val payload = md5.payload
        val actual = when {
            payload.size >= 34 && payload.copyOfRange(0, 32).all {
                (it.toInt().toChar() in '0'..'9') || (it.toInt().toChar() in 'a'..'f')
            } -> payload.copyOfRange(0, 32).toString(Charsets.US_ASCII)
            payload.size >= 18 -> payload.copyOfRange(0, 16)
                .joinToString("") { "%02x".format(it.toInt() and 255) }
            else -> error("ROM MD5: formato de respuesta desconocido")
        }
        val wanted = expected.joinToString("") { "%02x".format(it.toInt() and 255) }
        check(actual.equals(wanted, ignoreCase = true)) { "Verificación MD5 de flash fallida" }
        exchange(FlashCommands.FLASH_END, FlashCommands.endWithoutReboot(), 5000L)
        return wanted
    }
}
