package org.avoperformance.horse.update

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.SystemClock

internal const val ESPRESSIF_VID = 0x303A
internal const val USB_JTAG_SERIAL_PID = 0x1001
internal const val USB_PERMISSION_ACTION = "org.avoperformance.horse.update.USB_PERMISSION"

/**
 * CDC-ACM link to the ESP32-S3 USB-Serial-JTAG (VID 303A / PID 1001):
 * interface 0 = CDC control (SET_CONTROL_LINE_STATE drives the chip reset logic),
 * interface 1 = CDC data (bulk 0x01 OUT / 0x81 IN).
 */
internal class UsbCdcLink private constructor(
    private val manager: UsbManager,
    private val device: UsbDevice,
    private val connection: UsbDeviceConnection,
    private val control: UsbInterface?,
    private val data: UsbInterface,
    private val out: UsbEndpoint,
    private val input: UsbEndpoint
) : RomLink {
    @Volatile private var closed = false
    private var lastPresenceCheck = 0L
    private var present = true

    override val isOpen: Boolean
        get() {
            if (closed) return false
            val now = SystemClock.elapsedRealtime()
            if (now - lastPresenceCheck > 250) {
                lastPresenceCheck = now
                present = manager.deviceList.containsKey(device.deviceName)
            }
            return present
        }

    override fun write(data: ByteArray, timeoutMs: Int): Int {
        if (!isOpen) return -1
        var sent = 0
        while (sent < data.size) {
            val chunk = minOf(16384, data.size - sent)
            val n = connection.bulkTransfer(out, data, sent, chunk, timeoutMs)
            if (n <= 0) return if (sent > 0) sent else n
            sent += n
        }
        return sent
    }

    override fun read(buffer: ByteArray, timeoutMs: Int): Int {
        if (!isOpen) return -1
        return connection.bulkTransfer(input, buffer, buffer.size, timeoutMs)
    }

    override fun setLines(dtr: Boolean, rts: Boolean): Boolean {
        if (!isOpen) return false
        val value = (if (dtr) 1 else 0) or (if (rts) 2 else 0)
        val index = control?.id ?: 0
        return connection.controlTransfer(0x21, 0x22, value, index, null, 0, 1000) >= 0
    }

    override fun close() {
        if (closed) return
        closed = true
        runCatching { connection.releaseInterface(data) }
        control?.let { runCatching { connection.releaseInterface(it) } }
        runCatching { connection.close() }
    }

    companion object {
        fun findWatch(manager: UsbManager): UsbDevice? =
            manager.deviceList.values.firstOrNull { it.vendorId == ESPRESSIF_VID && it.productId == USB_JTAG_SERIAL_PID }
                ?: manager.deviceList.values.firstOrNull { it.vendorId == ESPRESSIF_VID }

        fun open(manager: UsbManager, device: UsbDevice): UsbCdcLink {
            val interfaces = (0 until device.interfaceCount).map { device.getInterface(it) }
            val data = interfaces.firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA && it.endpointCount >= 2 }
                ?: fail(Failure.NO_BOOTLOADER, "el dispositivo no tiene interfaz CDC de datos")
            val control = interfaces.firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_COMM }
            val eps = (0 until data.endpointCount).map { data.getEndpoint(it) }
            val out = eps.firstOrNull { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_OUT }
                ?: fail(Failure.NO_BOOTLOADER, "falta el endpoint bulk OUT")
            val input = eps.firstOrNull { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_IN }
                ?: fail(Failure.NO_BOOTLOADER, "falta el endpoint bulk IN")
            val connection = manager.openDevice(device) ?: fail(Failure.DISCONNECTED, "Android no pudo abrir el USB")
            if (!connection.claimInterface(data, true)) {
                connection.close(); fail(Failure.DISCONNECTED, "no se pudo reclamar la interfaz CDC")
            }
            control?.let { connection.claimInterface(it, true) }
            // 115200 8N1 (ignored by USB-Serial-JTAG, required by some CDC stacks before data flows)
            val coding = byteArrayOf(0x00, 0xC2.toByte(), 0x01, 0x00, 0, 0, 8)
            connection.controlTransfer(0x21, 0x20, 0, control?.id ?: 0, coding, coding.size, 1000)
            return UsbCdcLink(manager, device, connection, control, data, out, input)
        }
    }
}

/**
 * Waits for the watch to (re)appear after a reset and obtains USB permission.
 * After a chip reset Android sees a NEW device; unless the app was chosen as
 * default for it, Android asks for permission again and the user must accept.
 */
internal class AndroidDevicePort(
    private val context: Context,
    private val manager: UsbManager,
    private val onPermissionNeeded: () -> Unit
) : DevicePort {
    override fun open(timeoutMs: Long): RomLink {
        val start = SystemClock.elapsedRealtime()
        var deadline = start + timeoutMs
        var requestedFor: String? = null
        while (SystemClock.elapsedRealtime() < deadline) {
            val device = UsbCdcLink.findWatch(manager)
            if (device != null) {
                if (manager.hasPermission(device)) {
                    SystemClock.sleep(150) // let the CDC interface settle after enumeration
                    return UsbCdcLink.open(manager, device)
                }
                if (requestedFor != device.deviceName) {
                    requestedFor = device.deviceName
                    val pending = PendingIntent.getBroadcast(context, 0,
                        Intent(USB_PERMISSION_ACTION).setPackage(context.packageName),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                    manager.requestPermission(device, pending)
                    onPermissionNeeded()
                    deadline = maxOf(deadline, SystemClock.elapsedRealtime() + 60_000) // time for the user to tap
                }
            }
            SystemClock.sleep(100)
        }
        fail(Failure.DISCONNECTED, if (requestedFor != null) "permiso USB no concedido" else "el reloj no aparece por USB")
    }
}
