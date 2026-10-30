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

internal const val SILABS_VID = 0x10C4
internal const val WCH_VID = 0x1A86

/**
 * Every USB device this app can read: the ESP32-S3 USB-Serial/JTAG (chest watch),
 * Silicon Labs CP210x (Heltec V3 boards, back module) and CDC-ACM bridges such as
 * the WCH CH9102 / CH343.
 */
internal object UsbLinks {
    enum class Type(val text: String) { ESP_USB_JTAG("ESP32-S3 USB nativo"), CP210X("Silicon Labs CP210x"), CDC_UART("USB-UART CDC") }

    fun typeOf(d: UsbDevice): Type? = when {
        d.vendorId == ESPRESSIF_VID -> Type.ESP_USB_JTAG
        d.vendorId == SILABS_VID && d.productId in setOf(0xEA60, 0xEA70, 0xEA71, 0xEA63) -> Type.CP210X
        d.vendorId == WCH_VID && d.productId in setOf(0x55D2, 0x55D3, 0x55D4, 0x55D8) -> Type.CDC_UART
        (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA } -> Type.CDC_UART
        else -> null
    }

    fun find(manager: UsbManager): UsbDevice? =
        manager.deviceList.values.sortedBy { typeOf(it)?.ordinal ?: 99 }.firstOrNull { typeOf(it) != null }

    fun describe(d: UsbDevice): String = "%s (VID %04X · PID %04X)".format(typeOf(d)?.text ?: "desconocido", d.vendorId, d.productId)

    fun open(manager: UsbManager, device: UsbDevice): RomLink = when (typeOf(device)) {
        Type.CP210X -> Cp210xLink.open(manager, device)
        Type.ESP_USB_JTAG -> UsbCdcLink.open(manager, device)
        Type.CDC_UART -> UsbCdcLink.open(manager, device, LinkKind.UART_BRIDGE)
        null -> fail(Failure.NO_BOOTLOADER, "dispositivo USB no compatible")
    }
}

/** Silicon Labs CP210x vendor protocol (AN571): enable, 8N1, baud and DTR/RTS through control requests. */
internal class Cp210xLink private constructor(
    private val manager: UsbManager,
    private val device: UsbDevice,
    private val connection: UsbDeviceConnection,
    private val iface: UsbInterface,
    private val out: UsbEndpoint,
    private val input: UsbEndpoint,
) : RomLink {
    @Volatile private var closed = false
    private var lastCheck = 0L
    private var present = true
    override val kind get() = LinkKind.UART_BRIDGE

    override val isOpen: Boolean
        get() {
            if (closed) return false
            val now = SystemClock.elapsedRealtime()
            if (now - lastCheck > 250) { lastCheck = now; present = manager.deviceList.containsKey(device.deviceName) }
            return present
        }

    private fun ctl(request: Int, value: Int, data: ByteArray? = null) =
        connection.controlTransfer(REQTYPE_OUT, request, value, iface.id, data, data?.size ?: 0, 1000) >= 0

    override fun write(data: ByteArray, timeoutMs: Int): Int {
        if (!isOpen) return -1
        var sent = 0
        while (sent < data.size) {
            val n = connection.bulkTransfer(out, data, sent, minOf(out.maxPacketSize * 64, data.size - sent), timeoutMs)
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
        val value = MHS_WRITE_DTR or MHS_WRITE_RTS or (if (dtr) MHS_DTR else 0) or (if (rts) MHS_RTS else 0)
        return ctl(SET_MHS, value)
    }

    override fun setBaud(baud: Int): Boolean = isOpen && ctl(SET_BAUDRATE, 0, le32(baud.toLong()))

    override fun close() {
        if (closed) return
        closed = true
        runCatching { ctl(IFC_ENABLE, 0) }
        runCatching { connection.releaseInterface(iface) }
        runCatching { connection.close() }
    }

    companion object {
        private const val REQTYPE_OUT = 0x41
        private const val IFC_ENABLE = 0x00
        private const val SET_LINE_CTL = 0x03
        private const val SET_MHS = 0x07
        private const val PURGE = 0x12
        private const val SET_BAUDRATE = 0x1E
        private const val MHS_DTR = 0x0001
        private const val MHS_RTS = 0x0002
        private const val MHS_WRITE_DTR = 0x0100
        private const val MHS_WRITE_RTS = 0x0200

        fun open(manager: UsbManager, device: UsbDevice): Cp210xLink {
            val iface = device.getInterface(0)
            val eps = (0 until iface.endpointCount).map { iface.getEndpoint(it) }
            val out = eps.firstOrNull { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_OUT }
                ?: fail(Failure.NO_BOOTLOADER, "CP210x sin endpoint bulk OUT")
            val input = eps.firstOrNull { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_IN }
                ?: fail(Failure.NO_BOOTLOADER, "CP210x sin endpoint bulk IN")
            val connection = manager.openDevice(device) ?: fail(Failure.DISCONNECTED, "Android no pudo abrir el USB")
            if (!connection.claimInterface(iface, true)) { connection.close(); fail(Failure.DISCONNECTED, "no se pudo reclamar el CP210x") }
            val link = Cp210xLink(manager, device, connection, iface, out, input)
            if (!link.ctl(IFC_ENABLE, 1)) { link.close(); fail(Failure.DISCONNECTED, "el CP210x no se pudo activar") }
            link.ctl(SET_LINE_CTL, 0x0800)          // 8 data bits, no parity, 1 stop bit
            link.setBaud(115200)
            link.ctl(PURGE, 0x0F)
            return link
        }
    }
}

/** Opens any supported device, waiting for it to (re)appear and asking for USB permission. */
internal class AnyDevicePort(
    private val context: Context,
    private val manager: UsbManager,
    private val onPermissionNeeded: () -> Unit,
) : DevicePort {
    override fun open(timeoutMs: Long): RomLink {
        var deadline = SystemClock.elapsedRealtime() + timeoutMs
        var requestedFor: String? = null
        while (SystemClock.elapsedRealtime() < deadline) {
            val device = UsbLinks.find(manager)
            if (device != null) {
                if (manager.hasPermission(device)) {
                    SystemClock.sleep(150)
                    return UsbLinks.open(manager, device)
                }
                if (requestedFor != device.deviceName) {
                    requestedFor = device.deviceName
                    val pending = PendingIntent.getBroadcast(context, 0, Intent(USB_PERMISSION_ACTION).setPackage(context.packageName),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                    manager.requestPermission(device, pending)
                    onPermissionNeeded()
                    deadline = maxOf(deadline, SystemClock.elapsedRealtime() + 60_000)
                }
            }
            SystemClock.sleep(100)
        }
        fail(Failure.DISCONNECTED, if (requestedFor != null) "permiso USB no concedido" else "no aparece ningún dispositivo USB compatible")
    }
}
