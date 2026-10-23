package org.avoperformance.horse.update

/**
 * Byte transport to the ESP32-S3 (USB CDC on Android, simulator in tests).
 * Implementations must be usable from a single worker thread.
 */
internal interface RomLink {
    /** Writes all bytes or returns the number actually sent (negative on failure). */
    fun write(data: ByteArray, timeoutMs: Int): Int

    /** Reads up to buffer.size bytes; returns 0 or negative on timeout/failure. */
    fun read(buffer: ByteArray, timeoutMs: Int): Int

    /** CDC SET_CONTROL_LINE_STATE. Drives the USB-Serial-JTAG reset logic of the S3. */
    fun setLines(dtr: Boolean, rts: Boolean): Boolean

    /** False once the device is detached or the connection closed. */
    val isOpen: Boolean

    /** Releases the interface and closes the connection. Idempotent. */
    fun close()
}

/** Opens the watch, waiting for it to (re)appear on the bus and be authorized. */
internal interface DevicePort {
    fun open(timeoutMs: Long): RomLink
}

/**
 * DTR/RTS sequences from esptool (v4.8 reset.py) for the S3 USB-Serial-JTAG
 * peripheral. Lines are tracked like pyserial + Linux cdc-acm: a control
 * request is only sent when the state changes.
 */
internal class LineControl(private val link: RomLink, private val clock: Clock) {
    private var dtr = false
    private var rts = false
    private var initialised = false

    private fun apply(newDtr: Boolean, newRts: Boolean) {
        if (initialised && newDtr == dtr && newRts == rts) return
        dtr = newDtr; rts = newRts; initialised = true
        link.setLines(dtr, rts)
    }
    private fun setDtr(v: Boolean) = apply(v, rts)
    private fun setRts(v: Boolean) = apply(dtr, v)

    /** USBJTAGSerialReset: reset into the ROM download mode without pressing buttons. */
    fun resetIntoBootloader() {
        setRts(false); setDtr(false)
        clock.sleep(100)
        setDtr(true); setRts(false)
        clock.sleep(100)
        setRts(true); setDtr(false); setRts(true)
        clock.sleep(100)
        setDtr(false); setRts(false)
    }

    /** HardReset(uses_usb=True): run the application from flash. */
    fun hardReset() {
        setDtr(false)
        setRts(true)
        clock.sleep(200)
        setRts(false)
        clock.sleep(200)
    }
}

internal interface Clock {
    fun nowMs(): Long
    fun sleep(ms: Long)

    object System : Clock {
        override fun nowMs(): Long = java.lang.System.nanoTime() / 1_000_000L
        override fun sleep(ms: Long) { if (ms > 0) Thread.sleep(ms) }
    }
}

/** Error categories shown to the user. */
internal enum class Failure(val title: String) {
    DISCONNECTED("Reloj desconectado"),
    NO_BOOTLOADER("Bootloader no responde"),
    ROM_ERROR("El bootloader rechazó la operación"),
    INCOMPATIBLE("Firmware incompatible"),
    PARTITION("Partición no encontrada o tabla no válida"),
    UNSAFE("Operación bloqueada por seguridad"),
    WRITE_INTERRUPTED("Escritura interrumpida"),
    VERIFY_FAILED("Verificación fallida"),
    BOOT_NOT_CONFIRMED("Arranque no confirmado"),
    CANCELLED("Operación cancelada")
}

internal class UpdateException(val failure: Failure, detail: String, cause: Throwable? = null) :
    Exception(detail, cause) {
    val userMessage: String get() = "${failure.title}: $message"
}

internal fun fail(failure: Failure, detail: String): Nothing = throw UpdateException(failure, detail)

internal fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

internal fun u32le(bytes: ByteArray, p: Int): Long =
    (0..3).fold(0L) { a, i -> a or ((bytes[p + i].toLong() and 255L) shl (8 * i)) }

internal fun u16le(bytes: ByteArray, p: Int): Int =
    (bytes[p].toInt() and 255) or ((bytes[p + 1].toInt() and 255) shl 8)

internal fun le32(v: Long): ByteArray {
    require(v in 0..0xFFFF_FFFFL) { "Valor fuera de 32 bits: $v" }
    return ByteArray(4) { i -> (v ushr (8 * i)).toByte() }
}
