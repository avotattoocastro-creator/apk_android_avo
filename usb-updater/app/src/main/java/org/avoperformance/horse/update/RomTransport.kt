package org.avoperformance.horse.update

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint

/**
 * Bounded read-only ROM transport. Keeps partial SLIP frames across USB packets,
 * ignores stale responses to other opcodes and refuses write commands.
 */
internal class RomTransport(
    private val connection: UsbDeviceConnection,
    private val output: UsbEndpoint,
    private val input: UsbEndpoint
) {
    fun request(opcode: Int, payload: ByteArray, attempts: Int = 3): RomProtocol.Reply {
        require(opcode == 0x08 || opcode == 0x0A) { "Only ROM SYNC / READ_REG permitted" }
        require(attempts in 1..5)
        var lastError = "Sin respuesta"
        repeat(attempts) { attempt ->
            val encoded = RomProtocol.command(opcode, payload)
            val sent = connection.bulkTransfer(output, encoded, encoded.size, 1500)
            if (sent != encoded.size) {
                lastError = "Envío incompleto: $sent/${encoded.size}"
                return@repeat
            }
            val received = ArrayList<Byte>(1024)
            val deadline = android.os.SystemClock.elapsedRealtime() + 2000L
            while (android.os.SystemClock.elapsedRealtime() < deadline && received.size < 4096) {
                val chunk = ByteArray(512)
                val count = connection.bulkTransfer(input, chunk, chunk.size, 250)
                if (count <= 0) continue
                received.addAll(chunk.take(count))
                val reply = RomProtocol.decodeFrames(received.toByteArray())
                    .mapNotNull(RomProtocol::parseReply)
                    .firstOrNull { it.opcode == opcode }
                if (reply != null) {
                    if (reply.payload.size >= 2 &&
                        reply.payload.takeLast(2).all { it.toInt() == 0 }) return reply
                    lastError = "Respuesta ROM con estado de error"
                    break
                }
            }
            if (lastError == "Sin respuesta") lastError = "Tiempo agotado, intento ${attempt + 1}"
        }
        error("ROM $opcode: $lastError")
    }
}
